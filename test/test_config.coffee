config = require '../config/config'
mongoose  = require "mongoose"

# Arbitrary different port that doesn't clash with dev server
config.port = 8888
# Different database which we can nuke between tests.
config.dbname = "testintertwinkles"
# Fix the URLs.
config.short_url_base = "http://rly.shrt/r"
config.api_url = "http://localhost:8888"
config.api_key = "test-key-one"
config.authorized_keys = ["test-key-one"]
config.apps.www.url = config.api_url
config.apps.firestarter.url = "#{config.api_url}/firestarter"
config.apps.resolve.url = "#{config.api_url}/resolve"
config.apps.dotstorm.url = "#{config.api_url}/dotstorm"
config.apps.twinklepad.url = "#{config.api_url}/twinklepad"
config.email = {port: 2526}

module.exports = config
