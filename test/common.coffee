log4js = require 'log4js'
logger = log4js.getLogger()
logger.setLevel(log4js.levels.FATAL)

fs           = require 'fs'
_            = require 'underscore'
async        = require 'async'
expect       = require 'expect.js'
mongoose     = require 'mongoose'
connect      = require 'connect'
sockjs_client = require 'sockjs-client'
Schema       = mongoose.Schema
config       = require './test_config'
www_schema   = require('../lib/schema').load(config)
api_methods  = require("../lib/api_methods")(config)
server       = require '../lib/server'
fixture      = require './fixture'
email_server = require "../dev/email_server"
email        = require "emailjs"
mongoose     = require "mongoose"
uuid         = require 'node-uuid'
webdriver    = require 'selenium-webdriver'
SeleniumServer = require("selenium-webdriver/remote").SeleniumServer

module.exports = c = {}

selenium_server = null

c.fetchBrowser = (callback) ->
  build_browser = ->
    browser = new webdriver.Builder().usingServer(
        selenium_server.address()
      ).withCapabilities(
        webdriver.Capabilities.firefox()
      ).build()
    # Conveninece method for find by css selector
    browser.byCss = (selector) ->
      return browser.findElement(webdriver.By.css(selector))
    browser.byCsss = (selector) ->
      return browser.findElements(webdriver.By.css(selector))
    callback(browser)

  unless selenium_server?
    selenium_server = new SeleniumServer(config.testing.selenium_path, {port: 4444})
    selenium_server.start().then(build_browser)
  else
    build_browser()

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
try
  c.TestModel = mongoose.model("TestModel")
catch e
  c.TestModel = mongoose.model("TestModel", TestModelSchema)

c.no_err_args = (args) ->
  expect(args[0]).to.be(null)
  for i in [1...args.length]
    expect(args[i]).to.not.be(null)
    expect(args[i]).to.not.be(undefined)

c.await = (fn, timeout=100) ->
  if fn() == true
    return true
  setTimeout((-> c.await(fn, timeout)), timeout)

c.startUp = (done) ->
  log4js.getLogger("www").setLevel(log4js.levels.FATAL)
  srv = server.start(config)
  # Re-Squelch logging to preserve mocha's reporter
  logger.setLevel(log4js.levels.FATAL)
  log4js.getLogger("www").setLevel(log4js.levels.FATAL)

  async.series [
    (done) ->
      c.clearDb(done)
    (done) ->
      c.loadFixture(done)
  ], (err, res) ->
    expect(err).to.be(null)
    done(srv)

_mail_server_started = false

c.startMailServer = (callback) ->
  _mail_server_started = true
  mail = {
    server: null
    client: null
    callback: (->)
    outbox: []
  }
  mail.server = email_server.start( (message) ->
      mail.outbox.push(message)
      mail.callback(message)
    , config.email.port
    , ->
      mail.client = email.server.connect(config.email)
      callback(mail)
  )

c.shutDown = (srv, done) ->
  async.series([
    (done) ->
      if _mail_server_started
        _mail_server_started = false
        email_server.stop(done)
      else
        done()
    (done) -> srv.server.close() ; done()
    (done) -> c.clearDb(done)
    (done) -> srv.db.disconnect(done)
  ], done)

c.deleteIcons = (cb) ->
  www_schema.User.find {}, (err, docs) ->
    deletions = []
    _.each docs, (doc) ->
      _.each ["16", "32", "64"], (size) ->
        deletions.push (done) ->
          fs.unlink(__dirname + '/../uploads/' + doc.icon.sizes[size], done)
    async.parallel(deletions, cb)

c.clearDb = (cb) ->
  conn = mongoose.createConnection(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  conn.db.dropDatabase (err) ->
    expect(err).to.be(null)
    conn.close()
    cb()

c.loadFixture = (callback) ->
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

c.stubAuthenticate = (browser, email, callback) ->
  # Establish a session (if none exists) between browser and server. Then,
  # authenticate the session.
  authenticate = () ->
    c.stubBrowserID({email: email})
    user_done = "return intertwinkles.user && intertwinkles.user.get('email') == '#{email}';"

    browser.executeScript("intertwinkles._onlogout = function(){} ; " +
                          "intertwinkles._onlogin('mock assertion');")
    browser.wait ->
      browser.executeScript(user_done).then (result) ->
        if result == true
          callback(null)
        return result

  browser.executeScript("window.$ && $.cookie('express.sid')").then (cookie) ->
    if cookie
      authenticate()
    else
      browser.get("#{config.api_url}/").then(authenticate)

c.stubBrowserID = (browserid_response) ->
  persona = require("../lib/persona_consumer")
  persona.verify = (assertion, audience, callback, options) ->
    callback(null, _.extend {
      status: "okay"
      email: "test@mock"
      audience: "http://localhost:9000"
      expires: new Date().getTime() + 60*60*1000
      issuer: "mock-stub"
    }, browserid_response)


c.buildSockjsClient = (callback) ->
  client = sockjs_client.create("http://localhost:#{config.port}/sockjs")
  client.writeJSON = (data) =>
    client.write JSON.stringify(data)
  client.onceJSON = (func) =>
    client.once "data", (str) -> func(JSON.parse(str))
  client.on "connection", callback
  return client

c.identifiedSockjsClient = (server, session, email, callback) ->
  session.session_id = uuid.v4() unless session.session_id?
  session.anon_id = uuid.v4() unless session.anon_id?
  session.cookie = {maxAge: 20000} unless session.cookie?
  c.stubBrowserID({email: email})
  api_methods.authenticate session, "assertion", ->
    server.sockrooms.saveSession session, (err, session) =>
      expect(err).to.be(null)
      client = c.buildSockjsClient ->
        client.writeJSON {route: "identify", body: {session_id: session.session_id}}
        client.onceJSON (data) ->
          expect(data).to.eql(
            {route: "identify", body: {session_id: session.session_id}}
          )
          callback(client, session)

c.getAllUsersAndGroups = (callback) ->
  out = {
    users: {}
    groups: {}
  }
  www_schema.User.find {}, (err, users) ->
    return callback(err) if err?
    for user in users
      out.users[user.email] = user
    www_schema.Group.find {}, (err, groups) ->
      return callback(err) if err?
      for group in groups
        out.groups[group.slug] = group
      callback(null, out)

