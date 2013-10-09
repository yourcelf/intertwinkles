expect  = require 'expect.js'
config  = require './test_config'
common  = require './common'

timeoutSet = (a, b) -> setTimeout(b, a)

describe "registration", ->
  server = null
  browser = null

  before (done) ->
    common.startUp (theServer) ->
      server = theServer
      common.fetchBrowser (theBrowser) ->
        browser = theBrowser
        done()

  after (done) ->
    browser.quit().then -> common.shutDown(server, done)

  it "authenticates", (done) ->
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      done()

  it "logs out", (done) ->
    browser.executeScript("intertwinkles._onlogout();")
    .then ->
      is_logged_out = "return intertwinkles.user && intertwinkles.user.get('email') == null;"
      browser.wait ->
        browser.executeScript(is_logged_out).then (val) -> val
    .then -> done()

  it "registers a new account", (done) ->
    # Reload it because zombie borks when an internal redirect is triggered.
    # browsers...
    color = null
    common.stubAuthenticate browser, "new_account@example.com", (err) =>
      expect(err).to.be(null)
      # Give time for the modal to load.
      timeoutSet 500, =>
        # Check the modal, then add a name
        browser.byCss(".modal-scrollable h3").getText().then (text) ->
          expect(text).to.be("Ready in 1, 2, 3:")
        browser.byCss("[name=name]").sendKeys("Testy McTester")
        browser.byCss("input.color").click()
        browser.executeScript('return $("input.color").val();').then (theColor) ->
          color = theColor
        browser.executeScript("$($('div.profile-image')[2]).click();")
        browser.byCss("div.profile-image.chosen").getText().then (text) ->
          expect(text).to.be("Microwave Oven")
        browser.byCss(".modal-footer input.btn.btn-primary").click()
        browser.wait ->
          browser.getCurrentUrl().then (url) ->
            return url == "http://localhost:#{config.port}/about/starting/"
        browser.wait ->
          browser.byCss("h1").getText().then (text) ->
            return text == "Getting Started"
        browser.wait ->
          browser.executeScript("return $('.user-menu img').attr('src');").then (res) ->
            return res?
        browser.executeScript("return $('.user-menu img').attr('src');").then (res) =>
          expect(res).to.be(
            "http://localhost:#{config.port}/uploads/user_icons/#{color}-Microwave Oven-16.png"
          )
        browser.byCss(".user-menu .hidden-phone").getText().then (text) ->
          expect(text).to.be("Testy McTester")
          done()
