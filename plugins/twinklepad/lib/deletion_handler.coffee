_ = require 'underscore'
utils = require '../../../lib/utils'

module.exports = (config) ->
  schema = require("./schema").load(config)
  www_schema = require("../../../lib/schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.TwinklePad)
  return _.extend(handlers, {
    can_delete: (session, params, callback) ->
      ###
      TwinklePad doesn't set event types other than visit, so allow visits to
      count as contributions.
      ###
      schema.TwinklePad.findOne {
        _id: params.entity
        "sharing.group_id": {$exists: true},
      }, (err, doc) ->
        return callback(err) if err?
        return callback("Not found") unless doc?
        return callback(null, false) unless utils.can_edit(session, doc)
        return callback("Invalid url") unless doc.url == params.url
        return callback("Invalid title") unless doc.title == params.title
        author_ids = {}
        www_schema.Event.find {
          entity: params.entity
          user: {$exists: true}
        }, (err, docs) ->
          for doc in docs
            author_ids[doc.user?.toString() or doc.anon_id] = true
          match = {}
          match[session.auth.user_id] = true
          if _.isEqual author_ids, match
            return callback(null, "delete")
          return callback(null, "queue")

    delete_entity: (params, callback) ->
      padlib = require("./padlib")(config)
      ###
      Delete etherpad as well as mongoose document.
      ###
      schema.TwinklePad.findOne {_id: params.entity}, (err, doc) ->
        return callback(err) if err?
        return callback("Not found") unless doc?
        padlib.delete_pad doc, (err) ->
          return callback(err) if err?
          doc.remove (err) ->
            return callback(err)
  })
