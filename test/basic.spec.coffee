common = require './common'
expect = require 'expect.js'

await = (fn) ->
  if fn() == true
    return
  setTimeout (-> await fn), 100

describe "basic", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "Loads the front page", (done) ->
    @browser.visit "http://localhost:8888/", (blank, browser, status, errors) ->
      expect(status).to.be(200)
      done()

#  it "Mocks http requests", (done) ->
#    hot = "<html><head></head><body><h1>Hot!</h1></body></html>"
#    @browser.resources.mock "http://bogus.com/", {
#      statusCode: 200
#      headers: {}
#      body: hot
#    }
#
#    @browser.visit("http://bogus.com/")
#      .then =>
#        expect(@browser.html()).to.eql(hot)
#        done()
#      .fail (err) => done(new Error(err))
#
#  it "Mocks browserid", (done) ->
#    common.stubBrowserID(@browser, {email: "test@example"})
#    @browser.visit("https://login.persona.org/include.js")
#      .then =>
#        expect(@browser.text().indexOf("faux-assertion")).to.not.be(-1)
#        browserid = require("../node_modules/node-intertwinkles/node_modules/browserid-consumer")
#        browserid.verify "assertion", "audience-bogus.com", (err, data) ->
#          expect(err).to.be(null)
#          expect(data.email).to.be("test@example")
#          done()
#
#      .fail (err) => done(new Error(err))
#
#  it "Logs in", (done) ->
#    common.stubBrowserID(@browser, {email: "one@mockmyid.com"})
#    @browser.visit "http://localhost:8888/", (blank, browser, status, errors) ->
#      signin = ->
#        browser.evaluate("$('iframe')[0].contentWindow.navigator.id.request()")
#        await ->
#          username = browser.evaluate("intertwinkles.user.get('name')")
#          if username == "One"
#            done()
#            return true
#
#      await ->
#        signin_button = browser.evaluate("$('iframe')[0].contentWindow.document.getElementById('signin')")
#        if signin_button?
#          signin()
#          return true
