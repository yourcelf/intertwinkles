_ = require 'underscore'

module.exports = (config) ->
  schema = require("./schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.PointSet)
  return handlers

