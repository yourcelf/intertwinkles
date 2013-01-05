config = require '../config'
_ = require 'underscore'

# Use a different port from the config port, so we don't clash with a
# running dev server.

conf = _.extend {}, config
conf.port = 8127
conf.dbname = 'test'

module.exports = conf
