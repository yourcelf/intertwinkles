expect  = require 'expect.js'
_       = require 'underscore'
async   = require 'async'
config  = require '../../../test/test_config'
common  = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema = require('../../../lib/schema').load(config)
clock_schema = require("../lib/schema").load(config)
clock = require("../lib/clock")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

describe "clock", ->
  before (done) ->
    common.startUp (server) =>
      @server = server
      async.series [
        (done) =>
          # get all users and groups for convenience
          common.getAllUsersAndGroups (err, maps) =>
            @all_users = maps.users
            @all_groups = maps.groups
            done()
        (done) =>
          # Establish a session.
          @session = {}
          common.stubBrowserID({email: "one@mockmyid.com"})
          api_methods.authenticate(@session, "mock assertion", done)
        (done) =>
          # Build a clock to use.
          new clock_schema.Clock({
            name: "Meeting"
            sharing: { group_id: @all_groups["two-members"].id }
            present: [{
              name:    @all_users["one@mockmyid.com"].name
              user_id: @all_users["one@mockmyid.com"]._id
            }, {
              name:    @all_users["two@mockmyid.com"].name
              user_id: @all_users["two@mockmyid.com"]._id
            }]
          }).save (err, clock) =>
            @clock = clock
            done(err)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "has correct url", (done) ->
    expect(@clock.url).to.be("/c/#{@clock.id}/")
    expect(@clock.absolute_url).to.be("http://localhost:#{config.port}/clock/c/#{@clock.id}/")
    done()

  it "posts events", (done) ->
    clock.post_event @session, @clock, "create", {
      callback: (err, event) =>
        expect(err).to.be(null)
        expect(event.application).to.be("clock")
        expect(event.type).to.be("create")
        expect(event.entity).to.be(@clock.id)
        www_schema.Event.findOne {entity: @clock.id}, (err, doc) =>
          expect(err).to.be(null)
          expect(doc.id).to.be(event.id)
          expect(doc.entity).to.be(event.entity)
          expect("#{doc.group}").to.be(@clock.sharing.group_id)
          expect(doc.entity_url).to.be(@clock.url)
          done()
    }

  it "live about link", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit "#{config.apps.clock.url}/", (e, browser, status) ->
      expect(status).to.be(200)
      browser.clickLink(".about")
      # Check the about link.
      expect(browser.location.pathname).to.be("/clock/about/")
      expect(browser.text("h1")).to.be("About the Progressive Clock")
      done()
  
  it "live adds a clock", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit "#{config.apps.clock.url}/", (e, browser, status) ->
      browser.clickLink(".add-new-clock")
      expect(browser.location.pathname).to.be("/clock/add/")
      expect(browser.text("h1")).to.be("Add new Clock")
      done()

  it "live connects to detail page", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit @clock.absolute_url, (e, browser, status) ->
      expect(status).to.be(200)
      done()
