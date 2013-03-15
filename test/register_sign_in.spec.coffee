Browser = require 'zombie'
expect  = require 'expect.js'
_       = require 'underscore'
config  = require './test_config'
schema  = require('../lib/schema').load(config)
common  = require './common'

timeoutSet = (a, b) -> setTimeout(b, a)

describe "registration", ->
  this.timeout(20000)
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "authenticates", (done) ->
    common.stubAuthenticate @browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      done()

  it "logs out", (done) ->
    @browser.evaluate("intertwinkles.onlogout()")
    common.await =>
      if @browser.evaluate("intertwinkles.user && intertwinkles.user.get('email') == null")
        done()
        return true

  it "registers a new account", (done) ->
    # Reload it because zombie borks when an internal redirect is triggered.
    # browsers...
    @browser = common.fetchBrowser()
    common.stubAuthenticate @browser, "new_account@example.com", (err) =>
      expect(err).to.be(null)
      # Give time for the modal to load.
      timeoutSet 500, =>
        expect(@browser.text(".modal-scrollable h3")).to.be("Ready in 1, 2, 3:")
        @browser.fill("name", "Testy McTester")
        @browser.query("input.color").click()
        @color = @browser.evaluate('$("input.color").val()')
        @browser.evaluate("$($('div.profile-image')[2]).click()")
        expect(@browser.text("div.profile-image.chosen")).to.be("Microwave Oven")
        @browser.query(".modal-footer input.btn.btn-primary").click()
        # and thus we bork zombie.. time for new browser.
        done()

  it "redirects to 'getting started'", (done) ->
    @browser = common.fetchBrowser()
    @browser.visit "http://localhost:#{config.port}/", (e, browser) =>
      common.stubAuthenticate @browser, "new_account@example.com", (err) =>
        common.await =>
          if @browser.location.pathname == "/about/starting/"
            done()
            return true

  it "has the right icon and name", (done) ->
    @browser = common.fetchBrowser()
    @browser.visit "http://localhost:#{config.port}/about/starting/", (e, browser) =>
      common.stubAuthenticate @browser, "new_account@example.com", (err) =>
        common.await =>
          if @browser.text("h1") == "Getting Started"
            common.await =>
              if @browser.evaluate("$('.user-menu img').attr('src')")?
                expect(
                  @browser.evaluate("$('.user-menu img').attr('src')")
                ).to.be(
                  "http://localhost:#{config.port}/uploads/user_icons/" +
                  "#{@color}-Microwave Oven-16.png"
                )
                expect(@browser.text(".user-menu .hidden-phone")).to.be("Testy McTester")
                done()
                return true
            return true
