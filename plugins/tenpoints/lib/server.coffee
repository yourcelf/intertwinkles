_             = require 'underscore'
utils         = require '../../../lib/utils'

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  tenpoints = require("./tenpoints")(config)

module.exports = {start}
