expect      = require 'expect.js'
_           = require 'underscore'
async       = require 'async'
config      = require '../../../test/test_config'
common      = require '../../../test/common'
utils       = require "../../../lib/utils"
api_methods = require("../../../lib/api_methods")(config)
www_schema  = require('../../../lib/schema').load(config)
fs_schema   = require("../lib/schema").load(config)
fslib       = require("../lib/firestarter")(config)

describe "firestarter", ->
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
          api_methods.authenticate @session, "mock assertion", =>
            @session.anon_id = "anon_id_1"
            done()
        (done) =>
          @session2 = {}
          common.stubBrowserID({email: "two@mockmyid.com"})
          api_methods.authenticate @session2, "mock assertion", =>
            @session2.anon_id = "anon_id_2"
            done()
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "gets unused slugs", (done) ->
    fslib.get_unused_slug (err, slug) ->
      expect(err).to.be(null)
      expect(slug).to.not.be(null)
      done()


  it "creates a firestarter", (done) ->
    fslib.create_firestarter @session, {
      name: "Test"
      slug: "test"
      prompt: "How do my tests pass?"
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(doc.name).to.be("Test")
      expect(doc.slug).to.be("test")
      expect(doc.prompt).to.be("How do my tests pass?")
      expect(doc.url).to.be("/f/test")
      expect(doc.absolute_url).to.be(
        "http://localhost:#{config.port}/firestarter/f/test")
      expect(doc.responses.length).to.be(0)

      expect(event).to.not.be(null)
      expect(event.application).to.be("firestarter")
      expect(event.entity).to.eql(doc._id.toString())
      expect(event.type).to.be("create")
      expect(event.url).to.be(doc.url)
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.user.via_user).to.be(undefined)
      expect(event.group).to.be(undefined)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Firestarter"
        aspect: "\"Test\""
        collective: "new firestarters"
        verbed: "created"
        manner: ""
      })

      expect(si).to.not.be(null)
      expect(si.application).to.be("firestarter")
      expect(si.entity).to.be(doc.id)
      expect(si.type).to.be("firestarter")
      expect(si.url).to.be(doc.url)
      expect(si.absolute_url).to.be(doc.absolute_url)
      expect(si.title).to.be("Test")
      expect(si.summary).to.be("How do my tests pass? (0 responses)")
      expect(si.text).to.be("Test\nHow do my tests pass?")

      done()

  it "reads a firestarter", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) ->
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
  
      expect(event).to.not.be(null)
      expect(event.type).to.be("visit")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Test"
        aspect: ""
        collective: "visits"
        verbed: "visited"
        manner: ""
      })
      done()

  it "updates a firestarter", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      fslib.edit_firestarter @session, {
        _id: doc._id
        name: "New name"
        prompt: "And this is my prompty"
        sharing: {group_id: @all_groups["two-members"].id}
      }, (err, doc, event, si) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(doc.name).to.be("New name")
        expect(doc.prompt).to.be("And this is my prompty")
        expect(doc.sharing.group_id).to.be(@all_groups["two-members"].id)
        expect(doc.sharing.extra_viewers.length).to.be(0)
        expect(doc.sharing.extra_editors.length).to.be(0)
        expect(doc.sharing.public_edit_until).to.be(undefined)
        expect(doc.sharing.public_view_until).to.be(undefined)

        expect(event).to.not.be(null)
        expect(event.type).to.be("update")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(3)
        expect(terms[0]).to.eql({
          entity: "Firestarter"
          aspect: "the name"
          collective: "changed firestarters"
          verbed: "changed"
          manner: "from \"Test\" to \"New name\""
        })
        expect(terms[1]).to.eql({
          entity: "New name"
          aspect: "the prompt"
          collective: "changed firestarters"
          verbed: "changed"
          manner: "to \"And this is my prompty\""
        })
        expect(terms[2]).to.eql({
          entity: "New name"
          aspect: "the sharing settings"
          collective: "changed firestarters"
          verbed: "changed"
          manner: ""
        })

        expect(si).to.not.be(null)
        expect(si.sharing.group_id).to.be(@all_groups["two-members"].id)
        expect(si.summary).to.be("And this is my prompty (0 responses)")
        expect(si.text).to.be("New name\nAnd this is my prompty")
        done()

  it "adds a response (authenticated)", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      fslib.save_response @session, {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        response: "This is my response"
        firestarter_id: doc._id
      }, (err, firestarter, response, event, si) =>
        expect([false, true, true, true, true]).to.eql(
          (a? for a in [err, firestarter, response, event, si])
        )
        expect(firestarter.slug).to.be("test")
        expect(
          _.find(firestarter.responses, (r) -> r.toString() == response.id)?
        ).to.be(true)
        expect(response.firestarter_id.toString()).to.be(firestarter.id)
        expect(response.response).to.be("This is my response")
        expect(response.user_id.toString()).to.be(@session.auth.user_id)
        expect(response.name).to.be(@session.users[@session.auth.user_id].name)

        expect(event.type).to.be("append")
        expect(event.user.toString()).to.be(@session.auth.user_id)
        expect(event.via_user).to.be(undefined)
        expect(event.data.user.name).to.eql(response.name)
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "New name"
          aspect: "a response"
          collective: "added responses"
          verbed: "added"
          manner: "This is my response"
        })

        expect(si.summary).to.be("And this is my prompty (1 response)")
        expect(si.text).to.be("New name\nAnd this is my prompty\nThis is my response")
        done()

  it "adds a response (via another user)", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      fslib.save_response @session, {
        user_id: @session2.auth.user_id
        name: @session2.users[@session2.auth.user_id].name
        response: "Proxy response"
        firestarter_id: doc._id
      }, (err, firestarter, response, event, si) =>
        expect([false, true, true, true, true]).to.eql(
          (a? for a in [err, firestarter, response, event, si])
        )
        expect(firestarter.slug).to.be("test")
        expect(
          _.find(firestarter.responses, (r) -> r.toString() == response.id)?
        ).to.be(true)
        expect(response.user_id.toString()).to.be(@session2.auth.user_id)
        expect(response.name).to.be(@session2.users[@session2.auth.user_id].name)
        
        expect(event.type).to.be("append")
        expect(event.user.toString()).to.be(@session2.auth.user_id)
        expect(event.via_user.toString()).to.be(@session.auth.user_id)
        expect(event.data.user.name).to.eql(response.name)
        done()

  it "adds a response (as anonymous)", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      # Make it editable by anonymous.
      fslib.edit_firestarter @session, {
        _id: doc._id
        sharing: {group_id: null}
      }, (err, doc, event) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(utils.can_edit({}, doc)).to.be(true)

        fslib.save_response {}, {
          user_id: undefined
          name: "George"
          response: "Anonymous response"
          firestarter_id: doc._id
        }, (err, firestarter, response, event, si) =>
          expect([false, true, true, true, true]).to.eql(
            (a? for a in [err, firestarter, response, event, si])
          )
          expect(firestarter.slug).to.be("test")
          expect(
            _.find(firestarter.responses, (r) -> r.toString() == response.id)?
          ).to.be(true)
          expect(response.user_id).to.be(undefined)
          expect(response.name).to.be("George")
          
          expect(event.type).to.be("append")
          expect(event.user).to.be(undefined)
          expect(event.via_user).to.be(undefined)
          expect(event.data.user.name).to.eql("George")
          done()

  it "removes a response", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      start_length = doc.responses.length
      fslib.delete_response @session, {
        firestarter_id: doc._id
        _id: doc.responses[0]._id
      }, (err, firestarter, deleted_response, event, si) ->
        expect([false, true, true, true, true]).to.eql(
          (a? for a in [err, firestarter, deleted_response, event, si])
        )
        expect(firestarter.responses.length).to.be(start_length - 1)
        expect(
          _.find(firestarter.responses, (r) -> r.toString() == deleted_response.id)?
        ).to.be(false)

        expect(event).to.not.be(null)
        expect(event.type).to.be("trim")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "New name"
          aspect: "a response"
          collective: "removed responses"
          verbed: "removed"
          manner: "This is my response"
        })

        expect(si).to.not.be(null)
        expect(si.summary).to.be("And this is my prompty (2 responses)")
        expect(si.text).to.be(
          "New name\nAnd this is my prompty\nProxy response\nAnonymous response"
        )
        done()

  it "adds and removes a twinkle", (done) ->
    fslib.get_firestarter @session, {slug: "test"}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)

      res = doc.responses[0]
      fslib.post_twinkle @session, doc._id, res._id.toString(), (err, twinkle, firestarter, response) =>
        expect(err).to.be(null)
        expect(twinkle).to.not.be(null)
        expect(firestarter.id).to.be(doc.id)
        expect(response.id).to.be(res._id.toString())

        expect(twinkle.url).to.be(doc.url)
        expect(twinkle.recipient.toString()).to.be(response.user_id)
        expect(twinkle.sender.toString()).to.be(@session.auth.user_id)

        fslib.remove_twinkle @session, twinkle.id, firestarter.id, (err, delTwinkle) =>
          expect(err).to.be(null)
          expect(delTwinkle.id).to.be(twinkle.id)
          www_schema.Twinkle.find {application: "firestarter"}, (err, docs) ->
            expect(err).to.be(null)
            expect(docs.length).to.be(0)
            done()

