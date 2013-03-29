expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
common        = require '../../../test/common'
config        = require '../../../test/test_config'
api_methods   = require('../../../lib/api_methods')(config)

describe "Socket pointsets", ->
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

  pointset = null
  point = null

  it "creates a pointset", (done) ->
    @client.writeJSON {
      route: "points/save_pointset"
      body: {model: {name: "My Ten Point", slug: "my-ten-point"}}
    }
    @client.onceJSON (data) ->
      expect(data.route).to.be("points:pointset")
      expect(data.body.model._id).to.not.be(null)
      expect(data.body.model.name).to.be("My Ten Point")
      expect(data.body.model.slug).to.be("my-ten-point")
      pointset = data.body.model
      done()

  it "joins the room", (done) ->
    room = "points/#{pointset._id}"
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

  it "updates a pointset", (done) ->
    @client.writeJSON {
      route: "points/save_pointset"
      body: {model: {_id: pointset._id, name: "Your Ten Point"}}
    }
    async.map [@client, @client2], (client, done) ->
      client.onceJSON (data) ->
        expect(data).to.eql({
          route: "points:pointset",
          body: {model: _.extend {}, pointset, {name: "Your Ten Point"}}
        })
        pointset = data.body.model
        done()
    , done

  it "creates a point", (done) ->
    @client.writeJSON {
      route: "points/revise_point"
      body: {
        _id: pointset._id
        text: "Be excellent to each other."
        user_id: @session.auth.user_id
      }
    }
    async.map [@client, @client2],  (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:point")
        expect(data.body._id).to.be(pointset._id)
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
      route: "points/revise_point"
      body: {
        _id: pointset._id
        point_id: point._id
        text: "Party on, dudes."
        user_id: @session2.auth.user_id
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:point")
        expect(data.body._id).to.be(pointset._id)
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
      route: "points/support_point"
      body: {
        _id: pointset._id
        point_id: point._id
        user_id: @session.auth.user_id
        vote: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:support")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.user_id).to.be(@session.auth.user_id)
        expect(data.body.name).to.be(undefined)
        expect(data.body.vote).to.be(true)
        done()
    , done

  it "unsupports a point", (done) ->
    @client.writeJSON {
      route: "points/support_point"
      body: {
        _id: pointset._id
        point_id: point._id
        user_id: @session.auth.user_id
        vote: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:support")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.user_id).to.be(@session.auth.user_id)
        expect(data.body.name).to.be(undefined)
        expect(data.body.vote).to.be(false)
        done()
    , done

  it "sets editing", (done) ->
    @client.writeJSON {
      route: "points/set_editing"
      body: {
        _id: pointset._id
        point_id: point._id
        editing: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:editing")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.editing).to.eql([@session.anon_id])
        done()
    , done

  it "unsets editing", (done) ->
    @client.writeJSON {
      route: "points/set_editing"
      body: {
        _id: pointset._id
        point_id: point._id
        editing: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:editing")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.editing).to.eql([])
        done()
    , done

  it "checks a slug", (done) ->
    @client.writeJSON {
      route: "points/check_slug"
      body: { slug: "my-ten-point" }
    }
    @client.onceJSON (data) =>
      expect(data).to.eql({
        route: "points:check_slug"
        body: {ok: false}
      })

      @client.writeJSON {
        route: "points/check_slug"
        body: { slug: "another-slug" }
      }
      @client.onceJSON (data) =>
        expect(data).to.eql({
          route: "points:check_slug"
          body: {ok: true}
        })
        done()

  it "sets approved", (done) ->
    @client.writeJSON {
      route: "points/set_approved"
      body: {
        _id: pointset._id
        point_id: point._id
        approved: true
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:approved")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.approved).to.be(true)
        done()
    , done

  it "unsets approved", (done) ->
    @client.writeJSON {
      route: "points/set_approved"
      body: {
        _id: pointset._id
        point_id: point._id
        approved: false
      }
    }
    async.map [@client, @client2], (client, done) =>
      client.onceJSON (data) =>
        expect(data.route).to.be("points:approved")
        expect(data.body._id).to.be(pointset._id)
        expect(data.body.point_id).to.be(point._id)
        expect(data.body.approved).to.be(false)
        done()
    , done

  it "moves a point", (done) ->
    add_point = (cb) =>
      @client.writeJSON {
        route: "points/revise_point"
        body: {
          _id: pointset._id
          text: "Inconceivable!"
          user_id: undefined
          name: "Mua ha"
        }
      }
      async.map [@client, @client2], (client, done) =>
        client.onceJSON (data) =>
          expect(data.route).to.be("points:point")
          done()
      , cb

    async.series [
      # Add a couple more points first
      (done) -> add_point(done)
      (done) -> add_point(done)
      # Now practice moving
      (done) =>
        @client.writeJSON {
          route: "points/move_point"
          body: {
            _id: pointset._id
            point_id: point._id
            position: 0 # move it to the front -- adding unshifts, so
                        # point should be starting at position 2.
          }
        }
        async.map [@client, @client2], (client, done) =>
          client.onceJSON (data) =>
            expect(data.route).to.be("points:move")
            expect(data.body._id).to.be(pointset._id)
            expect(data.body.point_id).to.be(point._id)
            expect(data.body.position).to.be(0)
            done()
        , done
    ], done


