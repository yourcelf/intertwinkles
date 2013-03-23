expect      = require 'expect.js'
_           = require 'underscore'
async       = require 'async'
config      = require '../../../test/test_config'
common      = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema  = require('../../../lib/schema').load(config)
tp_schema   = require("../lib/schema").load(config)
tenpoints   = require("../lib/tenpoints")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

describe "tenpoints", ->
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
            @client = common.buildSockjsClient =>
              done()
        (done) =>
          @session2 = {}
          common.stubBrowserID({email: "two@mockmyid.com"})
          api_methods.authenticate @session2, "mock assertion", =>
            @session2.anon_id = "anon_id_2"
            @client2 = common.buildSockjsClient =>
              done()

      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "creates a tenpoint", (done) ->
    tenpoints.save_tenpoint @session, {
      model: {
        name: "My Ten Point"
        slug: "my-ten-point"
        sharing: {group_id: @all_groups['two-members'].id}
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(doc.name).to.be("My Ten Point")
      expect(doc.slug).to.be("my-ten-point")
      expect(p for p in doc.points).to.eql([])
      expect(doc.sharing.group_id).to.eql(@all_groups['two-members'].id)
      expect(doc.url).to.eql("/10/my-ten-point/")
      expect(doc.absolute_url).to.eql("http://localhost:8888/tenpoints/10/my-ten-point/")

      expect(event.application).to.be("tenpoints")
      expect(event.entity_url).to.be(doc.url)
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.type).to.be("create")
      expect(event.user.toString()).to.be(@all_users['one@mockmyid.com'].id)
      expect(event.via_user.toString()).to.be(event.user.toString())
      expect(event.group.toString()).to.eql(@all_groups['two-members'].id)
      expect(event.data).to.eql({name: "My Ten Point", slug: "my-ten-point"})

      expect(si.application).to.be("tenpoints")
      expect(si.entity).to.eql(doc.id)
      expect(si.url).to.eql(doc.url)
      expect(si.absolute_url).to.eql(doc.absolute_url)
      expect(si.type).to.be("tenpoint")
      expect(si.summary).to.be(doc.name)
      expect(si.title).to.be(doc.name)
      expect(si.sharing.group_id).to.eql(@all_groups['two-members'].id)
      expect(si.sharing.extra_editors.length).to.be(0)
      expect(si.sharing.extra_viewers.length).to.be(0)
      expect(si.sharing.advertise).to.be(undefined)
      expect(si.sharing.public_edit_until).to.be(undefined)
      expect(si.sharing.public_view_until).to.be(undefined)
      expect(si.text).to.be("My Ten Point")

      @tenpoint = doc
      done()

  it "updates a tenpoint", (done) ->
    tenpoints.save_tenpoint @session, {
      model: {
        _id: @tenpoint.id
        name: "Your Ten Point"
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(doc.name).to.be("Your Ten Point")
      expect(doc.slug).to.be("my-ten-point")
      expect(event.type).to.be("update")
      expect(si.text).to.be("Your Ten Point")

      @tenpoint = doc

      tp_schema.TenPoint.find {}, (err, docs) ->
        expect(err).to.be(null)
        expect(docs.length).to.be(1)
        www_schema.Event.find {application: "tenpoints"}, (err, docs) ->
          expect(err).to.be(null)
          expect(docs.length).to.be(2)
          www_schema.SearchIndex.find {application: "tenpoints"}, (err, docs) ->
            expect(err).to.be(null)
            expect(docs.length).to.be(1)
            done()

  it "adds a point", (done) ->
    tenpoints.revise_point @session, {
      _id: @tenpoint.id,
      text: "Be excellent to each other."
    }, (err, doc, point, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(doc.points.length).to.be(1)
      p = doc.points[0]
      expect(p.revisions.length).to.be(1)
      expect(p.revisions[0].text).to.be("Be excellent to each other.")
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.eql(
        @all_users['one@mockmyid.com'].id)
      @tenpoint = doc
      done()

  it "revises a point", (done) ->
    tenpoints.revise_point @session2, {
      _id: @tenpoint.id
      point_id: @tenpoint.points[0]._id.toString()
      text: "Party on, dude."
    }, (err, doc, point, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(doc.points.length).to.be(1)
      p = doc.points[0]
      expect(p.revisions.length).to.be(2)
      expect(p.revisions[0].text).to.be("Party on, dude.")
      expect(p.revisions[1].text).to.be("Be excellent to each other.")
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.eql(
        @all_users['two@mockmyid.com'].id
      )
      done()

  it "supports a point", (done) ->
    tenpoints.change_support @session, {
      _id: @tenpoint.id
      point_id: @tenpoint.points[0]._id.toString()
      user_id: @session.auth.user_id
      vote: true
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)

      p = doc.points[0]
      expect(p.revisions[0].supporters.length).to.be(2)
      supporter_ids = (
        s.user_id.toString() for s in p.revisions[0].supporters
      )
      expect(supporter_ids).to.eql([
        @session2.auth.user_id.toString(), @session.auth.user_id.toString()
      ])
      expect(event.type).to.be("vote")
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.via_user.toString()).to.be(@session.auth.user_id)
      expect(event.data.name).to.be("Your Ten Point")
      expect(event.data.action.support).to.be(true)
      expect(event.data.action.point_id.toString()).to.be(
        @tenpoint.points[0]._id.toString())
      expect(event.data.action.user_id.toString()).to.be(@session.auth.user_id)
      expect(event.data.action.name).to.be(undefined)
      done()

  it "unsupports a point", (done) ->
    # This will be @session unsupporting on behalf of @session2
    tenpoints.change_support @session, {
      _id: @tenpoint.id
      user_id: @session2.auth.user_id
      point_id: @tenpoint.points[0]._id.toString()
      vote: false
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(point._id).to.eql(doc.points[0]._id)
      p = doc.points[0]
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.be(
        @session.auth.user_id)
      expect(event.data.action.support).to.be(false)
      done()

  it "supports a point anonymously", (done) ->
    tenpoints.save_tenpoint @session, {
      model: {
        _id: @tenpoint.id
        sharing: {
          public_edit_until: new Date(new Date().getTime() + 100000)
          advertise: true
        }
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)
      expect(doc.sharing.public_edit_until > new Date()).to.be(true)

      tenpoints.change_support {}, {
        _id: @tenpoint.id
        user_id: null
        name: "George"
        point_id: @tenpoint.points[0]._id.toString()
        vote: true
      }, (err, doc, point, event) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(event).to.not.be(null)
        expect(point._id).to.eql(doc.points[0]._id)
        expect(doc.points[0].revisions[0].supporters.length).to.be(2)
        expect(doc.points[0].revisions[0].supporters[1].name).to.be("George")
        expect(doc.points[0].revisions[0].supporters[1].user_id).to.be(null)

        tenpoints.change_support {}, {
          _id: @tenpoint.id
          user_id: null
          name: "George"
          point_id: @tenpoint.points[0]._id.toString()
          vote: false
        }, (err, doc, point, event) =>
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          expect(point._id).to.eql(doc.points[0]._id)
          expect(doc.points[0].revisions[0].supporters.length).to.be(1)
          expect(doc.points[0].revisions[0].supporters[0].name).to.be(undefined)
          expect(
            doc.points[0].revisions[0].supporters[0].user_id.toString()
          ).to.be(
            @session.auth.user_id
          )
          done()

  it "fetches a tenpoint", (done) ->
    tenpoints.fetch_tenpoint "my-ten-point", {}, (err, doc) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(doc.id).to.be(@tenpoint.id)
      done()

  it "fetches a tenpoint list", (done) ->
    tenpoints.fetch_tenpoint_list @session, (err, docs) =>
      expect(err).to.be(null)
      expect(docs.group.length).to.be(1)
      expect(docs.group[0].id).to.be(@tenpoint.id)
      expect(docs.public.length).to.be(1)
      expect(docs.public[0].id).to.be(@tenpoint.id)

      tenpoints.fetch_tenpoint_list {}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.group.length).to.be(0)
        expect(docs.public.length).to.be(1)
        expect(docs.public[0].id).to.be(@tenpoint.id)
        done()

  it "indicates editing", (done) ->
    tenpoints.set_editing @session, {
      _id: @tenpoint._id
      point_id: @tenpoint.points[0]._id
      editing: true
    }, (err, doc) =>
      expect(doc.points[0].editing.length).to.be(1)
      expect(doc.points[0].editing[0]).to.be(@session.anon_id)
      done()

  it "stops indicating editing", (done) ->
    tenpoints.set_editing @session, {
      _id: @tenpoint._id
      point_id: @tenpoint.points[0]._id
      editing: false
    }, (err, doc) =>
      expect(doc.points[0].editing.length).to.be(0)
      done()

