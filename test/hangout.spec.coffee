expect        = require 'expect.js'
_             = require 'underscore'
http          = require 'http'
config        = require './test_config'
common        = require './common'
libxmljs      = require 'libxmljs'

describe "Hangout", ->
  server = null

  before (done) ->
    common.startUp (theServer) =>
      server = theServer
      done()

  after (done) ->
    common.shutDown(server, done)

  get_http_response = (url, callback) ->
    http.get url, (res) ->
      data = ''
      res.on 'data', (chunk) -> data += chunk
      res.on 'end', ->
        callback(null, res.statusCode, data)
    .on 'error', (e) ->
      callback(e)

  it "Publishes gadget xml file", (done) ->
    get_http_response "http://localhost:#{config.port}/hangout/gadget.xml", (err, status, data) ->
      expect(err).to.be(null)
      expect(status).to.be(200)
      xml = libxmljs.parseXml(data)
      expect(xml.get('//ModulePrefs').attr('title').value()).to.be("InterTwinkles")
      done()

  it "Publishes front page", (done) ->
    get_http_response "http://localhost:#{config.port}/hangout/", (err, status, data) ->
      expect(err).to.be(null)
      expect(status).to.be(200)
      done()
