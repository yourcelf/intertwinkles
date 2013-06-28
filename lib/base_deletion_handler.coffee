_ = require 'underscore'
utils = require "./utils"

###
This module defines a generic set of deletion handlers that should apply to
most cases. Override this with particular applications' definitions to handle
special needs.
###

module.exports = (config, BaseEntity) ->
  www_schema = require("./schema").load(config)

  return {
    can_trash: (session, params, callback) ->
      ###
      Can move things to the trash if you're able to edit the thing and it is
      assigned to a group.
      ###
      BaseEntity.findOne {
        _id: params.entity
        "sharing.group_id": {$exists: true}
      }, 'sharing', (err, doc) ->
        return callback(err) if err?
        return callback(null, doc and utils.can_edit(session, doc))

    can_delete: (session, params, callback) ->
      ###
      You can delete it if the only non-visit event recorded for this thing
      belongs to you.
      ###
      BaseEntity.findOne {
        _id: params.entity,
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
          type: {$ne: "visit"}
        }, (err, docs) ->
          for doc in docs
            author_ids[doc.user.toString()] = true

          match = {}
          match[session.auth.user_id] = true
          if _.isEqual author_ids, match
            return callback(null, "delete")
          return callback(null, "queue")

    trash_entity: (session, params, callback) ->
      ###
      Move to or from the trash by setting the "trash" parameter.
      ###
      BaseEntity.findOne {_id: params.entity}, (err, doc) ->
        return callback(err) if err?
        unless utils.can_edit(session, doc)
          return callback("Permission denied")
        doc.trash = !!params.trash
        doc.save (err, doc) -> return callback(err, doc)

    delete_entity: (params, callback) ->
      ###
      Delete by just calling "remove". Do this as a 2-step to trigger any
      removal hooks.
      ###
      BaseEntity.findOne {_id: params.entity}, (err, doc) ->
        return callback(err) if err?
        doc.remove (err) ->
          callback(err, doc)
  }





