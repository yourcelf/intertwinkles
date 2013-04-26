expect  = require 'expect.js'
config  = require './test_config'
common  = require './common'

timeoutSet = (a, b) -> setTimeout(b, a)

describe "creates and edits groups", ->
  this.timeout(40000)
  before (done) ->
    common.startUp (server) =>
      @server = server
      done()

  after (done) ->
    common.shutDown(@server, done)

  browser = null

  it "create group", (done) ->
    browser = common.fetchBrowser()
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      browser.visit "http://localhost:#{config.port}/groups/new", (e, browser) ->
        expect(browser.text("h1")).to.be("New group")
        browser.fill("name", "Affinito")
        browser.fill("#add_email", "two@mockmyid.com")
        browser.clickLink("a.add-new-invitee")
        expect(browser.queryAll(".newinvite").length).to.be(1)
        browser.query("form.form-horizontal").submit()
        common.await ->
          if browser.location.pathname == "/groups/show/affinito/"
            # We'd check for results here; but Zombie isn't re-parsing js after
            # a redirect, so we need to fetch a new browser first.
            done()
            return true

  it "has new group properties", (done) ->
    browser = common.fetchBrowser()
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      browser.visit "http://localhost:#{config.port}/groups/edit/affinito/", (e, browser) ->
        common.await ->
          if browser.queryAll("tr").length > 0
            expect(browser.queryAll(".newinvite").length).to.be(0)
            expect(browser.queryAll(".member").length).to.be(2)
            done()
            return true
