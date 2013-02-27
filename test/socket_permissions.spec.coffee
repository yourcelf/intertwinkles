expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
config        = require './test_config'
common        = require './common'
log4js        = require 'log4js'
api_methods = require("../lib/api_methods")(config)

fs_schema = require('../plugins/firestarter/lib/schema').load(config)
ds_schema = require('../plugins/dotstorm/lib/schema').load(config)
tp_schema = require('../plugins/twinklepad/lib/schema').load(config)
rs_schema = require('../plugins/resolve/lib/schema').load(config)
www_schema = require("../lib/schema").load(config)

logger = log4js.getLogger("socket_server")
logger.setLevel(log4js.levels.FATAL)

#
# This test suite verifies that the permissions to join a room for a socket are
# correctly handled.  One should only be able to join the socket for a document
# one has permission to access.
#

describe "Socket permissions", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      async.series [
        (done) =>
          www_schema.Group.findOne {name: "Two Members"}, (err, group) =>
            expect(err).to.be(null)
            @group = group
            done()
        (done) =>
          @user_map = {}
          www_schema.User.findOne {email: "one@mockmyid.com"}, (err, user) =>
            expect(err).to.be(null)
            @user = user
            done()
        (done) =>
          @sessions = {}
          authenticate = (user, done) =>
            @sessions[user.email] = {}
            common.stubBrowserID(@browser, {email: user.email})
            api_methods.authenticate(@sessions[user.email], "assertion", done)
          async.map(_.values(@user_map), authenticate, done)
        #
        # Build 3 users: anon, authenticated, and authorized.
        #
        (done) =>
          # anon
          @anony = common.build_sockjs_client(done)
        (done) =>
          # authenticated
          session = {cookie: { maxAge: 2000 }, session_id: "authenty"}
          @server.sockrooms.saveSession session, (err, ok) =>
            @authenty = common.build_sockjs_client =>
              @authenty.writeJSON {route: "identify", body: {session_id: "authenty"}}
              @authenty.onceJSON (data) ->
                expect(data).to.eql({route: "identify", body: {session_id: "authenty"}})
                done()
        (done) =>
          # authorized
          common.stubBrowserID(@browser, {email: "one@mockmyid.com"})
          session = {
            cookie: { maxAge: 2000 },
            session_id: "authory",
          }
          api_methods.authenticate session, "bogus assertion", (err, session, message) =>
            @server.sockrooms.saveSession session, (err, ok) =>
              @authory = common.build_sockjs_client =>
                @authory.writeJSON {route: "identify", body: {session_id: "authory"}}
                @authory.onceJSON (data) ->
                  expect(data).to.eql({route: "identify", body: {session_id: "authory"}})
                  done()
        #
        # Build two models for each app -- one that is private, one public.
        #
        (done) => @private = {sharing: group_id: @group.id} ; done()
        (done) => (@ds_public = new ds_schema.Dotstorm(slug: "public")).save(done)
        (done) => (@ds_private = new ds_schema.Dotstorm(
            _.extend({slug: "private"}, @private))).save(done)
        (done) => (@fs_public = new fs_schema.Firestarter({
            slug: "public", name: "public", prompt: "public"
          })).save(done)
        (done) => (@fs_private = new fs_schema.Firestarter(_.extend({
            slug: "private", name: "private", prompt: "private"
          }, @private))).save(done)
        (done) => (@rs_public = new rs_schema.Proposal()).save(done)
        (done) => (@rs_private = new rs_schema.Proposal(@private)).save(done)
        (done) => (@tp_public = new tp_schema.TwinklePad({
            # Add properties for pad_id to avoid attempting to contact etherpad
            # instance.
            pad_id: "bogus$public"
            pad_name: "public"
            read_only_pad_id: "bogus"
            etherpad_group_id: "bogus"
          })).save(done)
        (done) => (@tp_private = new tp_schema.TwinklePad(_.extend({
            # Add properties for pad_id to avoid attempting to contact etherpad
            # instance.
            pad_id: "bogus$private"
            pad_name: "private"
            read_only_pad_id: "bogus"
            etherpad_group_id: "bogus"
          }, @private))).save(done)
      ], done

  after (done) ->
    @anony.close()
    @authenty.close()
    @authory.close()
    common.shutDown(@server, done)


  check_all_rooms = (rooms) ->
    return (client_and_response, done) ->
      [client, response] = client_and_response
      async.mapSeries(rooms, (room, done) ->
        client.writeJSON {
          route: "join"
          body: {room: room}
        }
        client.onceJSON (data) ->
          switch response
            when "success"
              expect(data).to.eql({
                route: "join"
                body: {room: room, first: true}
              })
              # Absorb the "room_users" emission.
              client.onceJSON (data) ->
                expect(data.route).to.be("room_users")
                client.writeJSON {route: "leave", body: {room}}
                client.onceJSON (data) ->
                  expect(data).to.eql({
                    route: "leave", body: {room:room, last: true}
                  })
                  done()
            when "permission"
              expect(data).to.eql({
                route: "error"
                body: {error: "Permission to join #{room} denied."}
              })
              done()
            when "session"
              expect(data).to.eql({
                route: "error"
                body: {error: "Session not found."}
              })
              done()
            else
              expect(null).to.be("Response not recognized")
              done()
      , done)

  it "Authorizes properly for public rooms", (done) ->
    public_join_responses = [
      [@anony, "session"], [@authenty, "success"], [@authory, "success"]
    ]
    rooms = [ "dotstorm/#{@ds_public.id}", "firestarter/#{@fs_public.slug}",
              "resolve/#{@rs_public.id}",  "twinklepad/#{@tp_public.pad_id}"]
    async.mapSeries(public_join_responses, check_all_rooms(rooms), done)

  it "Authorizes properly for private rooms", (done) ->
    private_join_responses = [
      [@anony, "session"], [@authenty, "permission"], [@authory, "success"]
    ]
    rooms = [ "dotstorm/#{@ds_private.id}", "firestarter/#{@fs_private.slug}",
              "resolve/#{@rs_private.id}",  "twinklepad/#{@tp_private.pad_id}"]
    async.mapSeries(private_join_responses, check_all_rooms(rooms), done)
