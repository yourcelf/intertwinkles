expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
sockjs        = require 'sockjs'
sockjs_client = require 'sockjs-client'
express       = require 'express'
RedisStore    = require('connect-redis')(express)
config        = require './test_config'
RoomManager   = require('../lib/socket_server').RoomManager
log4js        = require 'log4js'
logger        = log4js.getLogger("socket_server")
logger.setLevel(log4js.levels.FATAL)
require "better-stack-traces"

build_client = (callback) ->
  client = sockjs_client.create("http://localhost:#{config.port}/sockjs")
  client.writeJSON = (data) =>
    client.write JSON.stringify(data)
  client.onceJSON = (func) =>
    client.once "data", (str) -> func(JSON.parse(str))
  client.on "connection", callback
  return client

await = (fn, timeout=100) ->
  if fn() == true
    return true
  setTimeout(fn, timeout)


describe "Socket server", ->
  before (done) ->
    sockserver = sockjs.createServer({
      log: (severity, message) -> logger[severity](message)
    })
    @rooms = new RoomManager(sockserver, new RedisStore())
    @app = express.createServer()
    sockserver.installHandlers(@app, {prefix: "/sockjs"})
    @app.listen(config.port)
    @client = build_client =>
      @client2 = build_client =>
        @client3 = build_client =>
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
    @rooms.addChannelAuth "room", (session, room, callback) ->
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
    @rooms.sessionStore.set "test-sid", @session, (err, ok) =>
      expect(err).to.be(null)
      
      @client.writeJSON {route: "identify", body: {session_id: "test-sid"}}
      @client.onceJSON (data) =>
        expect(data).to.eql({route: "identify", body: {session_id: "test-sid"}})
        expect(@rooms.sessionIdToSockets["test-sid"].length).to.be(1)
        socket = @rooms.sessionIdToSockets["test-sid"][0]
        expect(@rooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
        expect(_.keys(@rooms.roomToSockets).length).to.be(0)
        expect(_.keys(@rooms.socketIdToRooms).length).to.be(0)
        done()

  it "Accepts join room with session passing auth", (done) ->
    @client.writeJSON {route: "join", body: {room: "room/641a"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
      expect(_.keys(@rooms.roomToSockets).length).to.be(1)
      expect(_.keys(@rooms.socketIdToRooms).length).to.be(1)
      socket = @rooms.roomToSockets["room/641a"][0]
      expect(@rooms.socketIdToRooms[socket.sid]).to.eql(["room/641a"])
      expect(@rooms.sessionIdToSockets["test-sid"].length).to.be(1)
      expect(@rooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
      done()

  it "Receives an emission", (done) ->
    socket = @rooms.sessionIdToSockets["test-sid"][0]
    @rooms.socketEmit socket, "whatevs", {diggity: true}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "whatevs", body: {diggity: true}})
      done()

  it "Receives a broadcast", (done) ->
    @rooms.broadcast("room/641a", "hey", {oh: "yeah"})
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "hey", body: {oh: "yeah"}})
      done()

  it "Leaves a room", (done) ->
    @client.writeJSON {route: "leave", body: {room: "room/641a"}}
    @client.onceJSON (data) =>
      expect(data).to.eql({route: "leave", body: {room: "room/641a", last: true}})
      expect(@rooms.roomToSockets).to.eql({})
      expect(@rooms.socketIdToRooms).to.eql({})
      expect(@rooms.sessionIdToSockets["test-sid"].length).to.be(1)
      socket = @rooms.sessionIdToSockets["test-sid"][0]
      expect(@rooms.socketIdToSessionId[socket.sid]).to.be("test-sid")
      done()

  it "Handles multiple clients", (done) ->
    @session2 = {cookie: { maxAge: 2000 }, happy: false}
    @rooms.sessionStore.set "test-sid2", @session2, (err, ok) =>
      expect(err).to.be(null)
      @client2.writeJSON {route: "identify", body: {session_id: "test-sid2"}}
      @client2.onceJSON (data) =>
        expect(data).to.eql({route: "identify", body: {session_id: "test-sid2"}})
        vals = _.values(@rooms.socketIdToSessionId)
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
    @rooms.sessionStore.set "test-sid2", @session2, (err, ok) =>
      expect(err).to.be(null)
      # Have the first client re-join.
      @client.writeJSON {route: "join", body: {room: "room/641a"}}
      @client.onceJSON (data) =>
        expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
        # Have the second client join. Now there are two.
        @client2.writeJSON {route: "join", body: {room: "room/641a"}}
        @client2.onceJSON (data) =>
          expect(data).to.eql({route: "join", body: {room: "room/641a", first: true}})
          socket = @rooms.sessionIdToSockets["test-sid2"][0]
          vals = (sock.sid for sock in @rooms.roomToSockets["room/641a"])
          expect(@rooms.roomToSockets["room/641a"].length).to.be(2)
          expect(_.contains(vals, socket.sid)).to.be(true)
          expect(@rooms.socketIdToRooms[socket.sid]).to.eql(["room/641a"])
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
    @rooms.broadcast "room/641a", "hey", {you: "guys"}

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
        @rooms.broadcast "room/641a", "hey", {you: "three"}

  it "Leaves rooms on disconnect", (done) ->
    @client2.once "close", =>
      await =>
        if @rooms.roomToSockets["room/641a"].length == 1
          done()
          return true
      , 10
    @client2.close()

  it "Has empty structures after everyone disconnects", (done) ->
    @client.once "close", =>
      await =>
        if not @rooms.roomToSockets["room/641a"]?
          expect(@rooms.roomToSockets).to.eql({})
          expect(@rooms.socketIdToRooms).to.eql({})
          expect(@rooms.socketIdToSessionId).to.eql({})
          expect(@rooms.sessionIdToSockets).to.eql({})
          done()
          return true
      , 10
    @client.close()
