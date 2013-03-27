expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
common        = require '../../../test/common'
config        = require '../../../test/test_config'
api_methods   = require('../../../lib/api_methods')(config)

describe "Socket permissions", ->
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
          common.identifiedSockjsClient @server, @session, "one@mockmyid.com", (client) =>
            @client = client
            done()
        (done) =>
          @session2 = {}
          common.identifiedSockjsClient @server, @session2, "two@mockmyid.com", (client) =>
            @client2 = client
            done()
      ], done

  after (done) ->
    common.shutDown(@server, done)

  tenpoint = null
  point = null

  it "creates a tenpoint", (done) ->
    @client.writeJSON {
      route: "tenpoints/save_tenpoint"
      body: {model: {name: "My Ten Point", slug: "my-ten-point"}}
    }
    @client.onceJSON (data) ->
      expect(data.route).to.be("tenpoints:tenpoint")
      expect(data.body.model._id).to.not.be(null)
      expect(data.body.model.name).to.be("My Ten Point")
      expect(data.body.model.slug).to.be("my-ten-point")
      tenpoint = data.body.model
      done()

  it "joins the room", (done) ->
    room = "tenpoints/#{tenpoint._id}"
    @client.writeJSON {route: "join", body: {room}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "join", body: {room: room, first: true}})
      @client2.writeJSON {route: "join", body: {room}}
      async.parallel [
        (done) =>
          @client.onceJSON (data) =>
            expect(data.route).to.eql("room_users")
            done()
        (done) =>
          @client2.onceJSON (data) =>
            expect(data).to.eql({route: "join", body: {room: room, first: true}})
            @client2.onceJSON (data) ->
              expect(data.route).to.eql("room_users")
              done()
      ], done

  it "updates a tenpoint", (done) ->
    @client.writeJSON {
      route: "tenpoints/save_tenpoint"
      body: {model: {_id: tenpoint._id, name: "Your Ten Point"}}
    }
    async.map [@client, @client2], (client, done) ->
      client.onceJSON (data) ->
        expect(data).to.eql({
          route: "tenpoints:tenpoint",
          body: {model: _.extend {}, tenpoint, {name: "Your Ten Point"}}
        })
        tenpoint = data.body.model
        done()
    , done

  it "creates a point", (done) ->
    @client.writeJSON {
      route: "tenpoints/revise_point"
      body: {
        _id: tenpoint._id
        text: "Be excellent to each other."
      }
    }
    async.map [@client, @client2],  (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:point")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point.revisions.length).to.be(1)
        expect(data.body.point.revisions[0].text).to.be("Be excellent to each other.")
        expect(data.body.point.revisions[0].supporters.length).to.be(1)
        expect(data.body.point.revisions[0].supporters[0].user_id).to.be(
          @session.auth.user_id)
        point = data.body.point
        done()
    , done

  it "revises a point", (done) ->
    @client2.writeJSON {
      route: "tenpoints/revise_point"
      body: {
        _id: tenpoint._id
        point_id: point._id
        text: "Party on, dudes."
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:point")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point.revisions.length).to.be(2)
        expect(data.body.point.revisions[0].text).to.be("Party on, dudes.")
        expect(data.body.point.revisions[0].supporters.length).to.be(1)
        expect(data.body.point.revisions[0].supporters[0].user_id).to.be(
          @session2.auth.user_id)
        point = data.body.point
        done()
    , done

  it "supports a point", (done) ->
    @client2.writeJSON {
      route: "tenpoints/support_point"
      body: {
        _id: tenpoint._id
        point_id: point._id
        user_id: @session.auth.user_id
        vote: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:support")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.user_id).to.be(@session.auth.user_id)
        expect(data.body.name).to.be(undefined)
        expect(data.body.vote).to.be(true)
        done()
    , done

  it "unsupports a point", (done) ->
    @client.writeJSON {
      route: "tenpoints/support_point"
      body: {
        _id: tenpoint._id
        point_id: point._id
        user_id: @session.auth.user_id
        vote: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:support")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.user_id).to.be(@session.auth.user_id)
        expect(data.body.name).to.be(undefined)
        expect(data.body.vote).to.be(false)
        done()
    , done

  it "sets editing", (done) ->
    @client.writeJSON {
      route: "tenpoints/set_editing"
      body: {
        _id: tenpoint._id
        point_id: point._id
        editing: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:editing")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.editing).to.eql([@session.anon_id])
        done()
    , done

  it "unsets editing", (done) ->
    @client.writeJSON {
      route: "tenpoints/set_editing"
      body: {
        _id: tenpoint._id
        point_id: point._id
        editing: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:editing")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.editing).to.eql([])
        done()
    , done

  it "checks a slug", (done) ->
    @client.writeJSON {
      route: "tenpoints/check_slug"
      body: { slug: "my-ten-point" }
    }
    @client.onceJSON (data) =>
      expect(data).to.eql({
        route: "tenpoints:check_slug"
        body: {ok: false}
      })

      @client.writeJSON {
        route: "tenpoints/check_slug"
        body: { slug: "another-slug" }
      }
      @client.onceJSON (data) =>
        expect(data).to.eql({
          route: "tenpoints:check_slug"
          body: {ok: true}
        })
        done()

  it "sets approved", (done) ->
    @client.writeJSON {
      route: "tenpoints/set_approved"
      body: {
        _id: tenpoint._id
        point_id: point._id
        approved: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:approved")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.approved).to.be(true)
        done()
    , done

  it "unsets approved", (done) ->
    @client.writeJSON {
      route: "tenpoints/set_approved"
      body: {
        _id: tenpoint._id
        point_id: point._id
        approved: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("tenpoints:approved")
        expect(data.body._id).to.be(tenpoint._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.approved).to.be(false)
        done()
    , done

  it "moves a point", (done) ->
    add_point = (cb) =>
      @client.writeJSON {
        route: "tenpoints/revise_point"
        body: {
          _id: tenpoint._id
          text: "Inconceivable!"
        }
      }
      async.map [@client, @client2], (client, done) =>
        client.onceJSON (data) =>
          expect(data.route).to.be("tenpoints:point")
          done()
      , cb

    async.series [
      # Add a couple more points first
      (done) -> add_point(done)
      (done) -> add_point(done)
      # Now practice moving
      (done) =>
        @client.writeJSON {
          route: "tenpoints/move_point"
          body: {
            _id: tenpoint._id
            point_id: point._id
            position: 2 # move it to the end
          }
        }
        async.map [@client, @client2], (client, done) =>
          client.onceJSON (data) =>
            expect(data.route).to.be("tenpoints:move")
            expect(data.body._id).to.be(tenpoint._id)
            expect(data.body.point_id).to.be(point._id)
            expect(data.body.position).to.be(2)
            done()
        , done
    ], done


