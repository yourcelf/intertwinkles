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
  session = null
  session2 = null
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
      (done) ->
        session = {}
        common.stubBrowserID({email: "one@mockmyid.com"})
        api_methods.authenticate session, "mock assertion", ->
          session.anon_id = "anon_id_1"
          done()
      (done) ->
        session2 = {}
        common.stubBrowserID({email: "two@mockmyid.com"})
        api_methods.authenticate session2, "mock assertion", ->
          session.anon_id = "anon_id_2"
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
        expect(event.url).to.be("/p/tptest_1/")
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
    url = "#{config.apps.twinklepad.url}/p/tptest_2/"
    browser.visit url, (e, browser, status) =>
      tp_schema.TwinklePad.findOne {pad_name: "tptest_2"}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.be(null)
        done()

  it "trashes a twinklepad", (done) ->
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      doc.sharing.group_id = _.find(session.groups, (g) -> g.slug == "three-members").id
      doc.save (err, doc) ->
        api_methods.trash_entity session, {
          application: "twinklepad"
          entity: doc.id
          group: doc.sharing.group_id
          trash: true
        }, (err, event, si, doc) ->
          common.no_err_args([err, event, si, doc])
          expect(si.trash).to.be(true)
          expect(doc.trash).to.be(true)
          expect(event.type).to.be("trash")
          expect(event.absolute_url).to.be(doc.absolute_url)
          expect(event.url).to.be(doc.url)
          expect(event.entity).to.be(doc.id)
          expect(event.application).to.be("twinklepad")
          terms = api_methods.get_event_grammar(event)
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: doc.title
            aspect: "twinklepad"
            collective: "moved to trash"
            verbed: "moved to trash"
            manner: ""
          })
          done()

  it "untrashes a twinklepad", (done) ->
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      api_methods.trash_entity session2, {
        application: "twinklepad"
        entity: doc.id
        group: doc.sharing.group_id
        trash: false
      }, (err, event, si, doc) ->
        common.no_err_args([err, event, si, doc])
        expect(si.trash).to.be(false)
        expect(doc.trash).to.be(false)
        expect(event.type).to.be("untrash")
        expect(event.absolute_url).to.be(doc.absolute_url)
        expect(event.url).to.be(doc.url)
        expect(event.entity).to.be(doc.id)
        expect(event.application).to.be("twinklepad")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: doc.title
          aspect: "twinklepad"
          collective: "restored from trash"
          verbed: "restored from trash"
          manner: ""
        })
        done()

  it "requests deletion", (done) ->
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      # Ensure we have multiple events
      www_schema.Event.find {entity: doc._id}, (err, events) ->
        users = _.unique(_.map(events, (e) -> e.user?.toString() or "undefined"))
        expect(users.length > 1).to.be(true)

        # Request deletion
        api_methods.request_deletion session, {
          application: "twinklepad"
          entity: doc.id
          group: doc.sharing.group_id
          url: doc.url
          title: doc.title
        }, (err, dr, trashing, event, notices) ->
          common.no_err_args([err, dr, trashing, event, notices])
          [trash_event, si, doc] = trashing
          common.no_err_args([null, trash_event, si, doc])

          expect(doc.trash).to.be(true)
          expect(si.trash).to.be(true)

          expect(event.type).to.be("deletion")
          expect(event.url).to.be(dr.entity_url)
          expect(event.absolute_url).to.be(doc.absolute_url)
          expect(event.entity).to.be(doc.id)
          expect(event.application).to.be('twinklepad')
          terms = api_methods.get_event_grammar(event)
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: doc.title
            aspect: "twinklepad"
            collective: "requests to delete"
            verbed: "requested deletion"
            manner: "by #{event.data.end_date.toString()}"
          })
          done()

  it "confirms deletion", (done) ->
    tp_schema.TwinklePad.findOne {pad_name: "tptest_1"}, (err, doc) ->
      www_schema.DeletionRequest.findOne {entity: doc.id}, (err, dr) ->
        api_methods.confirm_deletion session2, dr._id, (err, notices) ->
          expect(err).to.be(null)
          expect(notices).to.be(undefined)
          tp_schema.TwinklePad.findOne {_id: doc._id}, (err, tdoc) ->
            expect(err).to.be(null)
            expect(tdoc).to.be(null)
            padlib.etherpad.getText {padID: doc.pad_id}, (err, data) ->
              expect(err).to.not.be(null)
              expect(err.message).to.be('padID does not exist')
              done()

