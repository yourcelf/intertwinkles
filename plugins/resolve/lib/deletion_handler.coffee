_ = require 'underscore'
utils = require "../../../lib/utils"

module.exports = (config) ->
  schema = require("./schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.Proposal)
  return _.extend(handlers, {
    trash_entity: (session, params, callback) ->
      ###
      Update notifications when trashing.
      ###
      resolvelib = require("./resolve")(config)
      schema.Proposal.findOne {_id: params.entity}, (err, proposal) ->
        return callback(err) if err?
        proposal.trash = !!params.trash
        proposal.save (err, doc) ->
          resolvelib.update_notifications session, doc, (err, notices) ->
            return callback(err, proposal, notices)
  })
