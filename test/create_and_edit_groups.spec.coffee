expect  = require 'expect.js'
config  = require './test_config'
common  = require './common'

describe "creates and edits groups", ->
  browser = null
  server = null

  before (done) ->
    common.startUp (theServer) =>
      server = theServer
      common.fetchBrowser (theBrowser) =>
        browser = theBrowser
        done()

  after (done) ->
    browser.quit().then -> common.shutDown(server, done)

  it "create group", (done) ->
    test_logo = __dirname + "/logo.png"
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      browser.get("http://localhost:#{config.port}/groups/new")
      browser.byCss("h1").getText().then (text) ->
        expect(text).to.be("New group")
      browser.byCss("[name=name]").sendKeys("Affinito")
      browser.byCss("#id_logo").sendKeys(test_logo)
      browser.byCss("#add_email").sendKeys("two@mockmyid.com")
      browser.byCss("a.add-new-invitee").click()
      browser.byCss(".newinvite").then (el) -> expect(el?).to.be(true)
      browser.byCss("form.form-horizontal").submit()
      browser.wait ->
        browser.byCsss(".membership-list li").then (lis) ->
          return lis.length == 1
      browser.byCss("#invited_members a").getText().then (text) ->
        expect(text).to.be("1 invited members")
        done()
