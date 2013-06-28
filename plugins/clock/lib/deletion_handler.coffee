_ = require 'underscore'

module.exports = (config) ->
  schema = require("./schema").load(config)
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
      return callback(null, false) unless utils.can_edit(session, doc)
      return callback("Invalid url") unless doc.url == params.url
      return callback("Invalid title") unless doc.title == params.title

      count = 0
      for cat in doc.categories
        count += times.length
      if count > 10
        callback(null, "queue")
      else
        callback(null, "delete")

  return handlers
