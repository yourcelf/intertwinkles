_     = require 'underscore'
async = require 'async'
utils = require "../../../lib/utils"

module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)
  c = {}

  c.post_event = (session, clock, type, opts) ->
    opts ?= {}
    event = _.extend {
      application: "clock"
      type: type
      entity_url: clock.url
      entity: clock.id
      user: session.auth?.user_id
      via_user: session.auth?.user_id
      anon_id: session.anon_id
      group: clock.sharing?.group_id
      data: {
        name: clock.name
        action: opts.data
      }
    }, opts.overrides or {}
    api_methods.post_event(event, opts.timeout or 0, opts.callback or (->))

  c.post_search_index = (clock, callback=(->)) ->
    search_data = {
      application: "clock"
      entity: clock.id
      type: "clock"
      url: clock.url
      title: clock.name
      summary: clock.about or(
        cat.name for cat in clock.categories).join(", ")
      sharing: clock.sharing
      text: [clock.name, clock.about or ""].concat(
        cat.name for cat in (clock.categories or [])
      ).join("\n")
    }
    api_methods.add_search_index(search_data, callback)

  c.fetch_clock_list = (session, callback) ->
    utils.list_accessible_documents schema.Clock, session, (err, docs) ->
      return callback(err) if err?
      return callback(null, docs)

  c.fetch_clock = (id, session, callback) ->
    schema.Clock.findOne {_id: id}, (err, doc) ->
      return callback(err) if err?
      return callback("Clock #{id} Not found") unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)
      return callback(null, doc)

  c.save_clock = (session, data, callback) ->
    return callback("Missing model param") unless data?.model
    schema.Clock.findOne {_id: data.model?._id}, (err, doc) ->
      return callback(err) if err?
      if not doc
        doc = new schema.Clock()
        type = "create"
      else
        type = "update"
      return callback("Permission denied") unless utils.can_edit(session, doc)
      delete data.model.sharing unless utils.can_change_sharing(session, doc)
      for key in ["name", "about", "present", "categories"]
        if data.model[key]?
          doc[key] = data.model[key]
      if data.model.sharing?
        _.extend(doc.sharing, data.model.sharing)
      doc.save (err, doc) ->
        return callback(err) if err?
        return callback("null doc") unless doc?
        async.parallel [
          (done) ->
            c.post_event session, doc, type, {callback: done}
          (done) ->
            c.post_search_index doc, done
        ], (err, results) ->
          return callback(err) if err?
          [event, si] = results
          return callback(null, doc, event, si)

  c.set_time = (session, data, callback) ->
    for key in ["_id", "category", "time", "index", "now"]
      return callback("Missing param #{key}") unless data[key]?
    schema.Clock.findOne {_id: data._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)
      category = _.find(doc.categories, (c) -> c.name == data.category)
      # Check that we're not out of sync -- time should be for the last param,
      # or be a new start.
      unless category? and (
          (data.index == category.times.length and not data.time.stop) or
          (data.index == category.times.length - 1 and data.time.stop))
        return callback("Out of sync", doc)
      #XXX: How to manage client clock skew? Do we trust them to do so?
      if data.index == category.times.length
        category.times.push(data.time)
      else
        category.times[data.index].start = data.time.start
        category.times[data.index].stop  = data.time.stop

      doc.save (err, doc) ->
        return callback(err) if err?
        callback(null, doc)

  return c
