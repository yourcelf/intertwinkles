_     = require "underscore"
async = require "async"
utils = require "../../../lib/utils"

module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)

  tp = {}

  tp.save_tenpoint = (session, data, callback) ->
    return callback("Missing model param") unless data?.model
    schema.TenPoint.findOne {_id: data.model._id}, (err, doc) ->
      return callback(err) if err?
      if not doc
        doc = new schema.TenPoint()
        event_type = "create"
      else
        event_type = "update"
      return callback("Permission denied") unless utils.can_edit(session, doc)
      delete data.model.sharing unless utils.can_change_sharing(session, doc)

      # Set fields
      for key in ["name", "slug"]
        doc[key] = data.model[key] if data.model[key]?
      if data.model.sharing?
        _.extend(doc.sharing, data.model.sharing)
      
      # Save
      doc.save (err, doc) ->
        return callback(err) if err?
        return callback("null doc") unless doc?
        tp.post_event_and_search session, doc, {type: event_type}, 0, (err, event, si) ->
          return callback(err) if err?
          return callback(null, doc, event, si)

  tp.post_event = (session, tenpoint, opts, timeout, callback) ->
    event = _.extend {
      application: "tenpoints"
      entity_url: tenpoint.url
      entity: tenpoint.id
      user: session.auth?.user_id
      via_user: session.auth?.user_id
      group: tenpoint.sharing?.group_id
      data: {
        name: tenpoint.name
        slug: tenpoint.slug
      }
    }, opts
    api_methods.post_event(event, timeout, callback)

  tp.post_search_index = (tenpoint, callback=(->)) ->
    search_data = {
      application: "tenpoints"
      entity: tenpoint.id
      type: "tenpoint"
      url: tenpoint.url
      summary: tenpoint.name
      title: tenpoint.name
      sharing: tenpoint.sharing
      text: [tenpoint.name].concat(
        point.revisions[0].text for point in tenpoint.points
      ).concat(
        point.revisions[0].text for point in tenpoint.drafts
      ).join("\n")
    }
    api_methods.add_search_index(search_data, callback)

  tp.post_event_and_search = (session, doc, event_opts, timeout, callback) ->
    async.parallel [
      (done) -> tp.post_event(session, doc, event_opts, timeout, done)
      (done) -> tp.post_search_index(doc, done)
    ], (err, results) ->
      return callback(err) if err?
      [event, si] = results
      return callback(err, event, si)

  tp.fetch_tenpoint_list = (session, callback) ->
    utils.list_accessible_documents schema.TenPoint, session, (err, docs) ->
      return callback(err) if err?
      return callback(null, docs)

  tp.fetch_tenpoint = (slug, session, callback) ->
    schema.TenPoint.findOne {slug: slug}, (err, doc) ->
      return callback(err) if err?
      return callback("Tenpoint #{slug} Not found") unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)
      return callback(null, doc)

  get_point = (session, data, required, callback) ->
    for key in required
      return callback("Missing param #{key}") unless data[key]?
    schema.TenPoint.findOne {_id: data._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)
      if data.point_id
        point = doc.find_point(data.point_id)
        if not point?
          return callback("Point with id #{data.point_id} not found")
      return callback(null, doc, point)

  tp.revise_point = (session, data, callback) ->
    get_point session, data, ["_id", "text"], (err, doc, point) ->
      return callback(err) if err?
      if not point?
        doc.drafts.push({ revisions: []})
        point = doc.drafts[doc.drafts.length - 1]

      point.revisions.unshift({})
      rev = point.revisions[0]
      rev.text = data.text
      rev.supporters = []
      rev.supporters.push({user_id: session.auth?.user_id, name: data.name})

      doc.save (err, doc) ->
        return callback(err) if err?
        return callback("null doc") unless doc?
        tp.post_event_and_search session, doc, {type: "update"}, 0, (err, event, si) ->
          return callback(err) if err?
          return callback(null, doc, point, event, si)

  tp.change_support = (session, data, callback) ->
    unless data.name or data.user_id
      return callback("Missing one of name or user_id")
    get_point session, data, ["_id", "point_id", "vote"], (err, doc, point) ->
      rev = point.revisions[0]
      supporter_matches = (s) -> return (
          (data.user_id? and s.user_id? and
            s.user_id.toString() == data.user_id.toString()) or
          ((not data.user_id?) and (not s.user_id?) and
            s.name? and data.name?  and s.name == data.name)
        )

      if data.vote
        unless _.find(rev.supporters, supporter_matches)
          rev.supporters.push({user_id: data.user_id, name: data.name})
      else
        rev.supporters = _.reject(rev.supporters, supporter_matches)

      doc.save (err, doc) ->
        return callback(err) if err?
        return callback("null doc") unless doc?
        tp.post_event session, doc, {
          type: "vote"
          user: data.user_id
          via_user: session.auth?.user_id
          data: {
            name: doc.name
            action: {
              support: data.vote
              point_id: point._id
              user_id: data.user_id
              name: data.name
            }
          }
        }, 0, (err, event) ->
          return callback(err) if err?
          return callback(null, doc, point, event)

  tp.set_editing = (session, data, callback) ->
    get_point session, data, ["_id", "point_id", "editing"], (err, doc, point) ->
      if data.editing
        point.editing.push(session.anon_id)
      else
        point.editing = _.without(point.editing, session.anon_id)
      doc.save (err, doc) -> callback(err, doc, point)

  tp.set_approved = (session, data, callback) ->
    get_point session, data, ["_id", "point_id", "approved"], (err, doc, point) ->
      is_approved = doc.is_approved(point)
      if data.approved == is_approved
        # No change -- must be out of sync.
        return callback("No change")
      else
        if data.approved
          # Move from drafts to points.
          doc.drafts = _.reject(doc.drafts, (p) -> p._id == point._id)
          doc.points.push(point)
        else
          # Move from points to drafts.
          doc.points = _.reject(doc.points, (p) -> p._id == point._id)
          doc.drafts.unshift(point)
        doc.save (err, doc) -> callback(err, doc, point)
  
  tp.move_point = (session, data, callback) ->
    get_point session, data, ["_id", "point_id", "position"], (err, doc, point) ->
      list = if doc.is_approved(point) then doc.points else doc.drafts
      if isNaN(data.position) or data.position < 0 or data.position >= list.length
        return callback("Bad position #{data.position}", doc)

      start_pos = null
      for p,i in list
        if p._id == point._id
          start_pos = i
          break
      unless start_pos?
        throw new Error("Unmatched point id #{point._id}")
      
      if start_pos == data.position
        # No change -- must be out of sync.
        return callback("No change", doc)

      # Remove the point from its current position.
      list.splice(start_pos, 1)
      # Insert it to the revised destination.
      list.splice(data.position, 0, point)
      doc.save (err, doc) -> callback(err, doc, point)

  return tp
