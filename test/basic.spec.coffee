common = require './common'
expect = require 'expect.js'

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
