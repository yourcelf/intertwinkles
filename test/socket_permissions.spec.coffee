expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
config        = require './test_config'
common        = require './common'
api_methods   = require("../lib/api_methods")(config)
schema        = require("../lib/schema").load(config)

#
# This test suite verifies that the permissions to join a room for a socket are
# correctly handled.  One should only be able to join the socket for a document
# one has permission to access.
#

describe "socket permissions", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      # Get maps of all groups and users for convenience.
      @group_map = {}
      async.series [
        (done) =>
          @group_map = {}
          schema.Group.find {}, (err, groups) =>
            for group in groups
              @group_map[group._id] = group
            done()
        (done) =>
          @user_map = {}
          schema.User.find {}, (err, users) =>
            for user in users
              @user_map[user.email] = user
            done()
        (done) =>
          @sessions = {}
          authenticate = (user, done) =>
            @sessions[user.email] = {}
            common.stubBrowserID(@browser, {email: user.email})
            api_methods.authenticate(@sessions[user.email], "assertion", done)
          async.map(_.values(@user_map), authenticate, done)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "Can join a public room when anonymous."
  it "Can join a public room when authenticated."
  it "Can't join a private room when anonymous."
  it "Can join a private room when authenticated and authorized."
  it "Can't join a private room when authenticated and not authorized."
