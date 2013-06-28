_ = require 'underscore'

module.exports = (config) ->
  schema = require("./schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.TwinklePad)
  return _.extend(handlers, {
    delete_entity: (params, callback) ->
      padlib = require("./padlib")(config)
      ###
      Delete etherpad as well as mongoose document.
      ###
      resolvelib = require("./resolve")(config)
      schema.TwinklePad.findOne {_id: params.entity}, (err, doc) ->
        padlib.delete_pad doc, (err) ->
          return callback(err) if err?
          doc.remove (err) ->
            return callback(err)
  })
