expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
sockjs        = require 'sockjs'
express       = require 'express'
RedisStore    = require('connect-redis')(express)
config        = require './test_config'
common        = require './common'
RoomManager   = require('../lib/socket_server').RoomManager
log4js        = require 'log4js'
logger        = log4js.getLogger("socket_server")
logger.setLevel(log4js.levels.FATAL)
require "better-stack-traces"

await = (fn, timeout=100) ->
  if fn() == true
    return true
  setTimeout(fn, timeout)


describe "Socket server", ->
  before (done) ->
    @sockserver = sockjs.createServer({
      log: (severity, message) -> logger[severity](message)
    })
    @sockrooms = new RoomManager(@sockserver, new RedisStore())
    @app = express.createServer()
    @sockserver.installHandlers(@app, {prefix: "/sockjs"})
    @app.listen(config.port)
    @client = common.build_sockjs_client =>
      @client2 = common.build_sockjs_client =>
        @client3 = common.build_sockjs_client =>
          done()

  after (done) ->
    @app.close()
    done()

  it "Returns error when joining without well-formed room", (done) ->
    @client.writeJSON {route: "join", whatever: "ok"}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Room not specified"}})
      done()

  it "Refuses join requests with bogus channel", (done) ->
    @client.writeJSON {route: "join", body: {room: "nonexistent"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Unknown channel"}})
      done()

  it "Refuses join requests with real channel, but no ident.", (done) ->
    # Create an authorization func for the room 'room': ensure that the session
    # is happy.
    @sockrooms.addChannelAuth "room", (session, room, callback) ->
      callback(null, session.happy == true)

    # Try to identify for the room, even though we don't have a session.
    @client.writeJSON {
      route: "join"
      body: {room: "room/641a"}
    }
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Session not found."}})
      done()

  it "Refuses identify without session ID", (done) ->
    @client.writeJSON {route: "identify", body: {not_session_id: "ok"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Missing session id"}})
      done()

  it "Refuses identify with unknown session ID", (done) ->
    @client.writeJSON {route: "identify", body: {session_id: "bogus"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Invalid session id"}})
      done()

  it "Accepts identify with known session ID", (done) ->
    @session = {cookie: { maxAge: 2000 }, happy: true}
    @sockrooms.sessionStore.set "test-sid", @session, (err, ok) =>
      expect(err).to.be(null)
      
      @client.writeJSON {route: "identify", body: {session_id: "test-sid"}}
      @client.onceJSON (data) =>
        expect(data).to.eql({route: "identify", body: {session_id: "test-sid"}})
        expect(@sockrooms.sessionIdToSockets["test-sid"].length).to.be(1)
        socket = @sockrooms.sessionIdToSockets["test-sid"][0]
        expect(@sockrooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
        expect(_.keys(@sockrooms.roomToSockets).length).to.be(0)
        expect(_.keys(@sockrooms.socketIdToRooms).length).to.be(0)
        done()

  it "Accepts join room with session passing auth", (done) ->
    @client.writeJSON {route: "join", body: {room: "room/641a"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
      expect(_.keys(@sockrooms.roomToSockets).length).to.be(1)
      expect(_.keys(@sockrooms.socketIdToRooms).length).to.be(1)
      socket = @sockrooms.roomToSockets["room/641a"][0]
      expect(@sockrooms.socketIdToRooms[socket.sid]).to.eql(["room/641a"])
      expect(@sockrooms.sessionIdToSockets["test-sid"].length).to.be(1)
      expect(@sockrooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
      done()

  it "Receives an emission", (done) ->
    socket = @sockrooms.sessionIdToSockets["test-sid"][0]
    @sockrooms.socketEmit socket, "whatevs", {diggity: true}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "whatevs", body: {diggity: true}})
      done()

  it "Receives a broadcast", (done) ->
    @sockrooms.broadcast("room/641a", "hey", {oh: "yeah"})
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "hey", body: {oh: "yeah"}})
      done()

  it "Leaves a room", (done) ->
    @client.writeJSON {route: "leave", body: {room: "room/641a"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "leave", body: {room: "room/641a", last: true}})
      expect(@sockrooms.roomToSockets).to.eql({})
      expect(@sockrooms.socketIdToRooms).to.eql({})
      expect(@sockrooms.sessionIdToSockets["test-sid"].length).to.be(1)
      socket = @sockrooms.sessionIdToSockets["test-sid"][0]
      expect(@sockrooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
      done()

  it "Handles multiple clients", (done) ->
    @session2 = {cookie: { maxAge: 2000 }, happy: false}
    @sockrooms.sessionStore.set "test-sid2", @session2, (err, ok) =>
      expect(err).to.be(null)
      @client2.writeJSON {route: "identify", body: {session_id: "test-sid2"}}
      @client2.onceJSON (data) =>
        expect(data).to.eql({route: "identify", body: {session_id: "test-sid2"}})
        vals = _.values(@sockrooms.socketIdToSessionId)
        vals.sort()
        expect(vals).to.eql(["test-sid", "test-sid2"])
        done()

  it "Refuses joining a room with session that doesn't pass auth", (done) ->
    @client2.writeJSON {route: "join", body: {room: "room/641a"}}
    @client2.onceJSON (data) =>
      expect(data).to.eql({route: "error", body: {error: "Permission to join room/641a denied."}})
      done()

  it "Handles 2 sockets in a room", (done) ->
    @session2.happy = true
    @sockrooms.sessionStore.set "test-sid2", @session2, (err, ok) =>
      expect(err).to.be(null)
      # Have the first client re-join.
      @client.writeJSON {route: "join", body: {room: "room/641a"}}
      @client.onceJSON (data) =>
        expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
        # Have the second client join. Now there are two.
        @client2.writeJSON {route: "join", body: {room: "room/641a"}}
        @client2.onceJSON (data) =>
          expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
          socket = @sockrooms.sessionIdToSockets["test-sid2"][0]
          vals = (sock.sid for sock in @sockrooms.roomToSockets["room/641a"])
          expect(@sockrooms.roomToSockets["room/641a"].length).to.be(2)
          expect(_.contains(vals, socket.sid)).to.be(true)
          expect(@sockrooms.socketIdToRooms[socket.sid]).to.eql(["room/641a"])
          done()

  it "Broadcasts to 2 sockets", (done) ->
    received_count = 0
    handle_receipt = (data) =>
      expect(data).to.eql({route: "hey", body: {you: "guys"}})
      received_count += 1
      if received_count == 2
        done()
    @client.onceJSON(handle_receipt)
    @client2.onceJSON(handle_receipt)
    @sockrooms.broadcast "room/641a", "hey", {you: "guys"}

  it "Supports 2 sockets for 1 session", (done) ->
    # Identify...
    @client3.writeJSON {route: "identify", body: {session_id: "test-sid"}}
    @client3.onceJSON (data) =>
      expect(data).to.eql {route: "identify", body: {session_id: "test-sid"}}
      # Join a room...
      @client3.writeJSON {route: "join", body: {room: "room/641a"}}
      @client3.onceJSON (data) =>
        expect(data).to.eql {route: "join", body: {room: "room/641a", first: false}}

        # Receive a broadcast.
        received_count = 0
        handle_receipt = (data) =>
          expect(data).to.eql({route: "hey", body: {you: "three"}})
          received_count += 1
          if received_count == 3
            @client3.once "close", done
            @client3.close()
        @client.onceJSON(handle_receipt)
        @client2.onceJSON(handle_receipt)
        @client3.onceJSON(handle_receipt)
        @sockrooms.broadcast "room/641a", "hey", {you: "three"}

  it "Leaves rooms on disconnect", (done) ->
    @client2.once "close", =>
      await =>
        if @sockrooms.roomToSockets["room/641a"].length == 1
          done()
          return true
      , 10
    @client2.close()

  it "Has empty structures after everyone disconnects", (done) ->
    @client.once "close", =>
      await =>
        if not @sockrooms.roomToSockets["room/641a"]?
          expect(@sockrooms.roomToSockets).to.eql({})
          expect(@sockrooms.socketIdToRooms).to.eql({})
          expect(@sockrooms.socketIdToSessionId).to.eql({})
          expect(@sockrooms.sessionIdToSockets).to.eql({})
          done()
          return true
      , 10
    @client.close()
