expect      = require 'expect.js'
_           = require 'underscore'
async       = require 'async'
mongoose    = require 'mongoose'
config      = require '../../../test/test_config'
common      = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema  = require('../../../lib/schema').load(config)
tp_schema   = require("../lib/schema").load(config)
padlib      = require("../lib/padlib")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

skip_tests = process.env.SKIP_ETHERPAD_TESTS

delete_all_test_pads = (callback) ->
  tp_schema.TwinklePad.find (err, docs) ->
    async.map docs, (doc, done) ->
      if doc.pad_name.substring(0, "tptest_".length) == "tptest_"
        padlib.delete_pad(doc, done)
      else
        done()
    , callback

describe "padlib", ->
  before (done) ->
    return done() if skip_tests
    async.series [
      (done) ->
        require("../bin/resync_etherpad_ids").run config, done

      (done) ->
        db = mongoose.connect(
          "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
        )
        delete_all_test_pads ->
          db.disconnect(done)

      (done) =>
        common.startUp (server) =>
          @server = server
          done()
    ], done

  after (done) ->
    return done() if skip_tests
    delete_all_test_pads =>
      common.shutDown(@server, done)

  it "Saves a pad", (done) ->
    return done() if skip_tests
    @timeout(20000)
    pad = new tp_schema.TwinklePad(pad_name: "tptest_1")
    pad.save (err, doc) ->
      expect(err).to.be(null)
      expect(doc.read_only_pad_id).to.not.be(null)
      done()

  it "Saves a pad with special chars", (done) ->
    return done() if skip_tests
    @timeout(20000)
    pad = new tp_schema.TwinklePad(pad_name: "tptest_test/url&chars%'=")
    pad.save (err, doc) ->
      expect(err).to.be(null)
      expect(doc.read_only_pad_id).to.not.be(null)
      done()

  it "Posts a twinklepad event", (done) ->
    return done() if skip_tests
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      expect(err).to.be(null)
      padlib.post_twinklepad_event {anon_id: "me"}, doc, "visit", {}, 0, (err, event) ->
        expect(err).to.be(null)
        expect(event).to.not.be(null)
        expect(event.application).to.be("twinklepad")
        expect(event.type).to.be("visit")
        expect(event.url).to.be("/p/tptest_1")
        expect(event.user).to.be(undefined)
        expect(event.anon_id).to.be("me")
        expect(event.group).to.be(undefined)
        expect(event.data).to.eql({entity_name: "tptest_1"})
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0].entity).to.be("tptest_1")
        expect(terms[0].aspect).to.be("")
        expect(terms[0].collective).to.be("visits")
        expect(terms[0].verbed).to.be("visited")
        expect(terms[0].manner).to.be("")
        done()

  it "Gets read-only html", (done) ->
    return done() if skip_tests
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      expect(err).to.be(null)
      padlib.get_read_only_html doc, (err, html) ->
        expect(err).to.be(null)
        expect(html).to.be("... edit me ...<br>")
        done()

  it "Creates a session", (done) ->
    return done() if skip_tests
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      expect(err).to.be(null)
      padlib.create_pad_session {}, doc, 500, (err, sess_id) ->
        expect(err).to.be(null)
        expect(/s\.[a-zA-Z0-9]{16}/.test(sess_id)).to.be(true)
        done()

  it "posts a search index", (done) ->
    return done() if skip_tests
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      expect(err).to.be(null)
      padlib.post_search_index doc, 0, (err, si) ->
        expect(err).to.be(null)
        expect(si.summary).to.be("... edit me ...\n")
        expect(si.title).to.be("tptest_1")
        done()

  it "immediately posts search index on creation", (done) ->
    return done() if skip_tests
    padlib.create_pad {}, {twinklepad: {pad_name: "tptest_3"}}, (err, doc, cookie, event, si) ->
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(doc.pad_name).to.be("tptest_3")
      expect(cookie.session_cookie).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)
      expect(si.entity).to.be(doc.id)
      done()

  it "cannot create a pad via url", (done) ->
    return done() if skip_tests
    browser = common.fetchBrowser()
    url = "#{config.apps.twinklepad.url}/p/tptest_2"
    browser.visit url, (e, browser, status) =>
      tp_schema.TwinklePad.findOne {pad_name: "tptest_2"}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.be(null)
        done()
