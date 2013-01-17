log4js = require 'log4js'
logger = log4js.getLogger()
logger.setLevel(log4js.levels.FATAL)

Browser = require 'zombie'
fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'
expect  = require 'expect.js'
mongoose= require 'mongoose'
Schema  = mongoose.Schema
config  = require './test_config'
www_schema = require('../lib/www/lib/schema').load(config)
ds_schema  = require('../lib/dotstorm/lib/schema')
server  = require '../lib/server'
fixture = require './fixture'
email_server = require "../lib/email_server"
email        = require "emailjs"

TestModelSchema = new Schema
  name: String
  sharing: {
    group_id: String
    public_view_until: Date
    public_edit_until: Date
    extra_viewers: [String]
    extra_editors: [String]
    advertise: Boolean
  }
TestModel = mongoose.model("TestModel", TestModelSchema)

startUp = (done) ->
  srv = server.start(config)
  # Squelch logging to preserve mocha's reporter
  logger.setLevel(log4js.levels.FATAL)
  browser = new Browser()
  # Prepare mail server
  mail = {
    server: null
    client: null
    callback: (->)
    outbox: []
  }
  async.series([
    (done) -> clearDb(done)
    (done) -> loadFixture(done)
    (done) ->
      mail.server = email_server.start( (message) ->
          mail.outbox.push(message)
          mail.callback(message)
        , config.email.port
        , ->
          mail.client = email.server.connect(config.email)
          done()
      )
  ], (res) ->
    done(srv, browser, mail))

shutDown = (srv, done) ->
  async.series([
    (done) -> email_server.stop(done)
    (done) -> srv.app.close() ; done()
    (done) -> clearDb(done)
    (done) -> srv.db.disconnect(done)
  ], done)

deleteIcons = (cb) ->
  www_schema.User.find {}, (err, docs) ->
    deletions = []
    _.each docs, (doc) ->
      _.each ["16", "32", "64"], (size) ->
        deletions.push (done) ->
          fs.unlink(__dirname + '/../lib/www/assets/' + doc.icon.sizes[size], done)
    async.parallel(deletions, cb)

clearDb = (cb) ->
  clearModel = (model, done) ->
    model.remove {}, (err) ->
      expect(err).to.be(null)
      model.find {}, (err, docs) ->
        expect(err).to.be(null)
        expect(docs.length).to.be(0)
        done()

  async.series([
    (done) -> deleteIcons(done),
    (done) ->
      async.map [
        www_schema.User, www_schema.Group, www_schema.Event,
        www_schema.Notification, www_schema.SearchIndex,
        www_schema.Twinkle, www_schema.ShortURL, TestModel
        ds_schema.Dotstorm, ds_schema.Idea, ds_schema.IdeaGroup
      ], clearModel, done
  ], cb)


loadFixture = (callback) ->
  users_by_name = {}

  userAdders = []
  _.each fixture.users, (user) ->
    userAdders.push (done) ->
      new www_schema.User(user).save (err, doc) ->
        expect(err).to.be(null)
        users_by_name[doc.name] = doc
        done(null)

  groupAdders = []
  _.each fixture.groups, (group) ->
    groupAdders.push (done) ->
      # Make a deep copy by serializing/unserializing.
      group = JSON.parse(JSON.stringify(group))
      for key in ["members", "past_members", "invited_members"]
        for member in group[key] or []
          if member.user?
            member.user = users_by_name[member.user]._id
          member.invited_by = users_by_name[member.invited_by]?._id or null

      model = new www_schema.Group(group)
      model.save (err, doc) ->
        expect(err).to.be(null)
        done(null)

  async.series([
    (done) -> async.parallel(userAdders, done),
    (done) -> async.parallel(groupAdders, done),
  ], callback)

stubBrowserID = (browser, browserid_response) ->
  browser.resources.mock "https://login.persona.org/include.js", {
    statusCode: 200
    headers: { "Content-Type": "text/javascript" }
    body: """
      var handlers = {};
      navigator.id = {
        _shimmed: true,
        _mocked: true,
        request: function() { handlers.onlogin("faux-assertion"); },
        watch: function(obj) { handlers = obj; },
        logout: function() { handlers.onlogout(); }
      };
    """
  }
  browserid = require("../node_modules/node-intertwinkles/node_modules/browserid-consumer")
  browserid.verify = (assertion, audience, callback, options) ->
    callback(null, _.extend {
      status: "okay"
      email: "test@mock"
      audience: "http://localhost:9000"
      expires: new Date().getTime() + 60*60*1000
      issuer: "mock-stub"
    }, browserid_response)

module.exports = {stubBrowserID, loadFixture, startUp, shutDown, TestModel}
