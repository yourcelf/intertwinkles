_ = require "underscore"
async = require "async"
utils = require "../../../lib/utils"
uuid = require 'node-uuid'
logger = require('log4js').getLogger()
rearranger = require("../assets/dotstorm/js/rearrange_groups")

module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)

  ds = {}

  ds.post_event = (session, dotstorm, event_type, event_data, timeout, callback) ->
    event_data.entity_name = dotstorm.name or "Untitled"
    api_methods.post_event({
        application: "dotstorm"
        type: event_type
        url: dotstorm.url
        entity: dotstorm._id
        user: session.auth?.user_id
        anon_id: session.anon_id
        group: dotstorm.sharing?.group_id
        data: event_data
      }, timeout, callback)

  ds.post_search_index = (doc, callback) ->
    unless doc?
      error = "Can't post search index for `#{doc}`"
      logger.error(error)
      return callback?(error)

    schema.Dotstorm.withLightIdeas {_id: doc._id}, (err, dotstorm) ->
      if err?
        logger.error(err)
        return callback?(err)
      unless dotstorm?
        error = "Dotstorm #{doc._id} not found."
        logger.error(error)
        return callback?(error)

      stuff = []
      stuff.push(dotstorm.name) if dotstorm.name?
      stuff.push(dotstorm.topic) if dotstorm.topic?

      untrash_count = 0
      for group in dotstorm.groups
        stuff.push(group.label) if group.label?
        for idea in group.ideas
          untrash_count += 1
          stuff.push(idea.description) if idea.description
          for tag in idea.tags or []
            stuff.push(tag)

      if stuff.length > 0
        search_data = {
          application: "dotstorm"
          entity: dotstorm._id
          type: "dotstorm"
          url: "/d/#{dotstorm.slug}/"
          title: dotstorm.name or "Untitled dotstorm"
          summary: "#{dotstorm.topic or ""} " +
            "(#{untrash_count} idea#{if untrash_count == 1 then "" else "s"})"
          text: stuff.join("\n")
          sharing: dotstorm.sharing
        }
        api_methods.add_search_index(search_data, callback)
      else
        callback(null, null)

  ds.post_event_and_search = (session, doc, event_type, event_data, callback) ->

  #
  # Save changes to a dotstorm (including creating a new one). Post appropriate
  # events and search indexes.
  #
  _save_dotstorm = (session, doc, data, event_type, callback) ->
    return callback("Permission denied") unless utils.can_edit(session, doc)
    return callback("Missing param") unless data?.dotstorm?
    # Log the event
    event_data = {}
    for key in ["name", "topic"]
      if data.dotstorm[key]? and doc[key]? and data.dotstorm[key] != doc[key]
        event_data["old_" + key] = doc[key]
        event_data[key] = data.dotstorm[key]

    # Set the changes to the model. Note that we ommit changes to ordering and
    # trash here; those are handled separately to avoid data loss.
    for key in ["slug", "name", "topic"]
      if data.dotstorm[key]
        doc.set key, data.dotstorm[key]

    # Maybe update sharing
    if utils.can_change_sharing(session, doc) and data.dotstorm.sharing?
      unless utils.sharing_is_equal(doc.sharing, data.dotstorm.sharing)
        utils.update_sharing(doc, data.dotstorm.sharing)
        event_data.sharing = utils.clean_sharing({}, data.dotstorm)
        # Makes sure we can still edit sharing.
        unless utils.can_change_sharing(session, doc)
          return callback("Permission denied")

    doc.save (err, doc) ->
      return callback(err) if err?
      async.parallel [
        (done) ->
          if event_type == "create" or (not _.isEqual(event_data, {}))
            ds.post_event(session, doc, event_type, event_data, 0, done)
          else
            done()
        (done) ->
          ds.post_search_index(doc, done)
      ], (err, results) ->
        [event, search_index] = results
        return callback(err, doc, event, search_index)
  
  ds.create_dotstorm = (session, data, callback) ->
    _save_dotstorm(session, new schema.Dotstorm(), data, "create", callback)

  ds.edit_dotstorm = (session, data, callback) ->
    unless data?.dotstorm?._id?
      return callback("Missing param")
    schema.Dotstorm.findOne {_id: data.dotstorm._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)
      _save_dotstorm(session, doc, data, "update", callback)

  ds.rearrange = (session, data, callback) ->
    return callback("Missing param _id") unless data?.dotstorm?._id?
    return callback("Missing baseline groups") unless data?.dotstorm?.groups?
    return callback("Missing baseline trash") unless data?.dotstorm?.trash?
    return callback("Missing movement") unless data?.movement?.length == 5

    # Build a query that ensures that the version of the dotstorm we want to
    # rearrange is the same that's in the DB.
    atomic_condition = {
      _id: data.dotstorm._id
      groups: {$size: data.dotstorm.groups.length}
      trash: {$size: data.dotstorm.trash.length}
    }
    for group,i in data.dotstorm.groups
      atomic_condition["groups.#{i}.ideas"] = {$size: group.ideas.length}
      for idea_id,j in group.ideas
        atomic_condition["groups.#{i}.ideas.#{j}"] = idea_id
    for idea_id,i in data.dotstorm.trash
      atomic_condition["trash.#{i}"] = idea_id

    # Query first to check permissions.
    schema.Dotstorm.findOne atomic_condition, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)

      # Do the rearranging.
      result = rearranger.rearrange(doc.groups, doc.trash, data.movement)
      if result == false
        return callback("Invalid rearrangement")

      # Update atomically.
      schema.Dotstorm.findOneAndUpdate atomic_condition, {
        groups: doc.groups
        trash: doc.trash
      }, (err, doc) ->
        return callback(err) if err?
        ds.post_search_index doc, (err, si) ->
          callback(err, doc, si)

  ds.edit_group_label = (session, data, callback) ->
    return callback("Missing dotstorm._id") unless data?.dotstorm?._id
    unless data?.group?._id and data?.group?.label
      return callback("Missing group fields")
    schema.Dotstorm.findOne {_id: data.dotstorm._id}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)
      schema.Dotstorm.findOneAndUpdate {
        _id: data.dotstorm._id,
        'groups._id': data.group._id
      }, {
        $set: {'groups.$.label': data.group.label}
      }, (err, doc) ->
        return callback(err) if err?
        return callback("Not found") unless doc?
        return callback(null, doc)

  ds.get_dotstorm = (session, data, callback) ->
    unless data?.dotstorm?._id or data?.dotstorm?.slug
      return callback("Missing dotstorm")
    query = {}
    query._id = data.dotstorm._id if data.dotstorm._id
    query.slug = data.dotstorm.slug if data.dotstorm.slug

    schema.Dotstorm.findOne query, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)
      schema.Idea.findLight {dotstorm_id: doc._id}, (err, light_ideas) ->
        return callback(err) if err?
        light_ideas or= []
        ds.post_event session, doc, "visit", {}, 60 * 1000 * 5, (err, event) ->
          callback(err, doc, light_ideas, event)

  #
  # Ideas
  #
  _save_idea = (session, dotstorm, idea, data, event_type, callback) ->
    for key in ["dotstorm_id", "description", "background", "tags",
                "drawing", "votes", "photoData"]
      if data.idea[key]?
        idea[key] = data.idea[key]
    if not data.idea.tags? and data.idea.taglist?
      idea.taglist = data.idea.taglist
    idea.dotstorm_id = dotstorm._id
    idea.background ?= '#ffffdd'
    idea.description ?= ""
    idea.save (err, idea) ->
      return callback(err) if err?
      return callback("Null idea") unless idea?
      event_data = {
        is_new: event_type == "create"
        description: idea.description
        image: idea.drawingURLs.small
      }
      ds.post_event session, dotstorm, "append", event_data, (err, event) ->
        return callback(err, idea, event)

  ds.create_idea = (session, data, callback) ->
    return callback("Missing dotstorm._id") unless data?.dotstorm?._id
    return callback("Missing idea") unless data?.idea?
    schema.Dotstorm.findOne {_id: data.dotstorm._id}, (err, dotstorm) ->
      return callback(err) if err?
      return callback("Not found") unless dotstorm?
      return callback("Permission denied") unless utils.can_edit(session, dotstorm)
      idea = new schema.Idea()
      _save_idea session, dotstorm, idea, data, "create", (err, idea, event) ->
        return callback(err) if err?
        # Since idea saving can take time, do the insert to dotstorm
        # atomically. Go through schema.Dotstorm.collection to access the
        # native driver, rather than mongoose, as mongoose's casting breaks the
        # "-1" set position which gives a front-of-array push.
        #
        # Set the _id to a uuid to maintain consistency with client groups.
        schema.Dotstorm.collection.update {_id: dotstorm._id}, {
          $set: {"groups.-1": {_id: uuid.v4(), ideas: [ idea._id ]}}
        }, (err, numModified, rawResponse) ->
          return callback(err) if err?
          async.parallel [
            (done) ->
              ds.post_search_index dotstorm, (err, si) -> done(err, si)
            (done) ->
              schema.Dotstorm.findOne {_id: dotstorm._id}, (err, doc) ->
                done(err, doc)
          ], (err, results) ->
            return callback(err) if err?
            [si, dotstorm] = results
            return callback(err, dotstorm, idea, event, si)

  ds.edit_idea = (session, data, callback) ->
    return callback("Missing idea") unless data?.idea?._id
    schema.Idea.findOne {_id: data.idea._id}, (err, idea) ->
      return callback(err) if err?
      return callback("Not found") unless idea?
      schema.Dotstorm.findOne {_id: idea.dotstorm_id}, (err, dotstorm) ->
        unless utils.can_edit(session, dotstorm)
          return callback("Permission denied")
        _save_idea session, dotstorm, idea, data, "update", (err, idea, event) ->
          return callback(err) if err?
          ds.post_search_index dotstorm, (err, si) ->
            return callback(err, dotstorm, idea, event, si)

  ds.get_idea = (session, data, callback) ->
    return callback("Missing idea._id") unless data?.idea?._id
    schema.Idea.findOne {_id: data.idea._id}, (err, idea) ->
      return callback(err) if err?
      return callback("Not found") unless idea?
      schema.Dotstorm.findOne {_id: idea.dotstorm_id}, 'sharing', (err, doc) ->
        return callback("Permission denied") unless utils.can_view(session, doc)
        callback(err, doc, idea)

  return ds
