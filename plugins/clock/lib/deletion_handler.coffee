_ = require 'underscore'
utils = require '../../../lib/utils'

module.exports = (config) ->
  schema = require("./schema").load(config)
  www_schema = require('../../../lib/schema').load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.Clock)
  handlers.can_delete = (session, params, callback) ->
    ###
    Clock doesn't log non-visit events for anything but editing and creating
    the name and categories of a clock.  Instead, go by a heuristic for the number
    of speaking turns logged.
    ###
    schema.Clock.findOne {
      _id: params.entity,
      "sharing.group_id": {$exists: true},
    }, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback(null, false) unless utils.can_edit(session, doc)
      return callback("Invalid url") unless doc.url == params.url
      return callback("Invalid title") unless doc.title == params.title

      www_schema.Event.find {
        entity: params.entity
        user: {$exists: true}
        type: {$ne: "visit"}
      }, (err, events) ->
        return callback(err) if err?
        author_ids = {}
        for event in events
          author_ids[event.user.toString()] = true

        match = {}
        match[session.auth.user_id] = true
        if _.isEqual author_ids, match
          count = 0
          for cat in doc.categories
            count += cat.times.length
          if count > 10
            return callback(null, "queue")
          return callback(null, "delete")
        return callback(null, "queue")



  return handlers
