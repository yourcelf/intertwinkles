_ = require 'underscore'
utils = require "../../../lib/utils"
module.exports = (config) ->
  schema = require("./schema").load(config)
  return {
    can_trash: (session, params, callback) ->
      schema.Proposal.findOne {_id: params.entity}, 'sharing', (err, doc) ->
        return callback(err) if err?
        return callback(null, doc and utils.can_edit(session, doc))

    can_delete: (session, params, callback) ->
      schema.Proposal.findOne {_id: params.entity}, (err, doc) ->
        return callback(err) if err?
        return callback(null, false) unless utils.can_edit(session, doc)
        return callback("Invalid url") unless doc.url == params.url
        return callback("Invalid title") unless doc.title == params.title
        author_ids = {}
        for rev in doc?.revisions or []
          author_ids[rev.user_id] = true
        for opinion in doc?.opinions or []
          author_ids[opinion.user_id] = true
        for resolution in doc?.resolutions or []
          author_ids[resolution.user_id] = true

        match = {}
        match[session.auth.user_id] = true
        if _.isEqual author_ids, match
          return callback(null, "delete")
        return callback(null, "queue")

    trash_entity: (session, params, callback) ->
      resolvelib = require("./resolve")(config)
      schema.Proposal.findOne {_id: params.entity}, (err, proposal) ->
        return callback(err) if err?
        unless utils.can_edit(session, proposal)
          return callback("Permission denied")
        proposal.trash = !!params.trash
        proposal.save (err, doc) ->
          resolvelib.update_notifications session, doc, (err, notices) ->
            return callback(err, proposal, notices)

    delete_entity: (params, callback) ->
      schema.Proposal.findOne {_id: params.entity}, 'sharing', (err, proposal) ->
        return callback(err) if err?
        proposal.remove (err) ->
          callback(err, proposal)
  }
