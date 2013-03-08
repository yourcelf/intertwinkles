###
This module implements a room connection and authorization process for
websockets; written with the intention of being more or less agnostic for the
socket library used (i.e. keeping it relatively abstract so it could be swapped
out), but with sockjs as that built-in library.

Rooms are aware of both the sockets that are connected to each room, and the
session associated with each socket.  Every socket has one session; any session
may have one or more sockets (probably one per tabs/window/iframe).

The workflow proceeds as follows.  For the server:

1. Server constructs a RoomManager instance with a session store (probably a
RedisStore shared with express).
2. The application adds "channel" authorization methods using @addChannelAuth.
3. Render a page for the client, including a session_id corresponding to the
@sessionStore in some manner that is accessible to the client socket that is
connecting.
4. When the client sends a message to an authorized room, the RoomManager will
emit a "channel/name" event with the message body, socket, and session.

For the client:

1. After establishing a connection, before any other activity, the client must
send the message:
  { route: "identify", session_id: <session_id> }
using the session_id provided by the server. Server acknowledges receipt with a
message to "identify" with the received session_id.

2. After identifying, the client can join rooms by sending the message:
  { route: "join", room: "channel/name" }
The 'channel' part of the name should correspond to one of the channel auth
methods registered by the server.  The name is whatever the application needs
to route messages within the channel. Server acknowledges join with a message
to "join" with the joined room channel/name.

3. To send messages to a room, the client issues:
  { route: "channel/name", body: {...message body...} }

4. To leave a room, the client issues:
  { route: "leave", room: "channel/name" }
Server acknowledges with message to "leave" with the left room channel/name.

###
events  = require 'events'
_       = require 'underscore'
logger  = require("log4js").getLogger("socket_server")
uuid    = require "node-uuid"
async   = require "async"
connect = require "connect"

class RoomManager extends events.EventEmitter
  constructor: (socketServer, sessionStore, secret) ->
    @channelAuth = {}
    # Allow blank channel without authorization.
    @addChannelAuth "", (session, room, cb) -> cb(null, true)
    @sessionStore = sessionStore
    @secret = secret

    # Keep track of which sessions are in which rooms
    @roomToSockets = {}   # Room path to array of sockets
    @socketIdToRooms = {}   # Socket IDs to an array of rooms
    
    # Keep track of which sockets associate with which sessions.
    @socketIdToSessionId = {}
    @sessionIdToSockets = {}

    # The actual socket handler.
    @sockjs = socketServer
    @sockjs.on "connection", (socket) =>
      socket.on "data", (message) =>
        try
          data = JSON.parse(message)
        catch e
          return @handleError(socket, "Invalid JSON")
        @route socket, data
      socket.on "close", =>
        @disconnect(socket)
      socket.sid = uuid.v4()
      socket.sendJSON = (route, data) => @socketEmit(socket, route, data)

  addChannelAuth: (channel, authFunc) => @channelAuth[channel] = authFunc
  removeChannelAuth: (channel) => delete @channelAuth[channel]

  route: (socket, message) =>
    return unless message.route?
    if message.route == "identify"
      return @identify(socket, message?.body?.session_id)
    else if message.route == "join"
      return @join(socket, message?.body?.room)
    else if message.route == "leave"
      return @leave(socket, message.body?.room or {})
    else
      @_getSessionForSocket socket, (err, session) =>
        return @handleError(socket, err) if err?
        return @handleError(socket, "Missing session") if not session?
        @emit message.route, socket, session, message.body or {}

  getSessionsInRoom: (room, callback) =>
    session_ids = []
    for socket in @roomToSockets[room] or []
      session_ids.push(@socketIdToSessionId[socket.sid])
    session_ids = _.unique(session_ids)
    async.map(session_ids, (sid, done) =>
      @sessionStore.get(sid, done)
    , callback)

  getRoomsForSessionId: (session_id) =>
    rooms = []
    for socket in @sessionIdToSockets[session_id] or []
      rooms = rooms.concat(@socketIdToRooms[socket.sid])
    rooms = _.unique(rooms)
    return rooms

  #
  # Socket emissions
  #

  socketEmit: (socket, route, msg) =>
    if socket.readyState == 1 # 0-connecting, 1-open, 2-closing, 3-closed
      socket.write JSON.stringify({route: route, body: msg})

  broadcast: (room, route, msg, exclude=null) =>
    for socket in @roomToSockets[room] or []
      if socket.sid == exclude
        continue
      @socketEmit(socket, route, msg)

  handleError: (socket, err) =>
    logger.error(err)
    if socket?
      @socketEmit socket, "error", {error: err}

  #
  # Workflow
  #

  identify: (socket, raw_session_id) =>
    return @handleError(socket, "Missing session id") unless raw_session_id?
    session_id = connect.utils.parseSignedCookie(raw_session_id, @secret)
    
    # remove existing socket/session association if needed.
    prev_session_id = @socketIdToSessionId[socket.sid]
    if prev_session_id? and prev_session_id != session_id
      @sessionIdToSockets[prev_session_id] = _.filter(
        @sessionIdToSockets[prev_session_id],
        (sock) -> sock.sid == socket.sid
      )

    # Verify session exists by retrieving it from the store.
    @sessionStore.get session_id, (err, session) =>
      return @handleError(socket, err) if err?
      return @handleError(socket, "Invalid session id") unless session?

      # Associate socket / session
      @socketIdToSessionId[socket.sid] = session_id
      unless @sessionIdToSockets[session_id]?
        @sessionIdToSockets[session_id] = []
      @sessionIdToSockets[session_id].push(socket)
      respond = => @socketEmit(socket, "identify", {session_id: session_id})
      if not session.anon_id or not session.session_id
        if not session.anon_id
          session.anon_id = uuid.v4()
        session.session_id = session_id
        @sessionStore.set session_id, session, (err, ok) =>
          return @handleError(socket, err) if err?
          respond()
      else
        respond()

  saveSession: (session, callback) =>
    if not session.session_id?
      return callback("session_id not found")
    @sessionStore.set session.session_id, session, (err, ok) =>
      return callback(err) if err?
      return callback(null, session)

  join: (socket, room, verify=true) =>
    # Ignore any message that doesn't have a matching auth channel.
    return @handleError(socket, "Room not specified") unless room?
    channel = room.split("/")[0]
    return @handleError(socket, "Unknown channel") unless @channelAuth[channel]?
    @_getSessionForSocket socket, (err, session) =>
      return @handleError(socket, err) if err?
      @channelAuth[channel](session, room, (err, authorized) =>
        return @handleError(socket, err) if err?
        if authorized
          @joinWithoutAuth(socket, session, room)
        else
          @handleError(socket, "Permission to join #{room} denied.")
      )

  joinWithoutAuth: (socket, session, room, options) =>
    @roomToSockets[room] ?= []
    @socketIdToRooms[socket.sid] ?= []
    first = false
    if not _.contains(@socketIdToRooms[socket.sid], room)
      # Find out if our session has any other sockets in this room.
      session_id = @socketIdToSessionId[socket.sid]
      # 'first' refers to first in this *session*. If we have another
      # window open here, it will be a different socket, and this could
      # be first for the *socket*.  But we want first for the sesssion in
      # order to trigger updates of room user lists and such, which list
      # sessions, not sockets.
      first = _.every(@roomToSockets[room], (sock) =>
        @socketIdToSessionId[sock.sid] != session_id
      )
      # Add the socket/room association.
      @roomToSockets[room].push(socket)
      @socketIdToRooms[socket.sid].push(room)

    # Announce to any RoomManager listeners that this socket has joined.
    unless options?.silent
      emission = {socket, session, room, first}
      @emit "join", emission
      # Reply to the socket, acknowledging the join.
      socket_emission = {room, first}
      @socketEmit socket, "join", socket_emission

  leave: (socket, room) =>
    return @handleError(socket, "Room not specified") unless room?
    # First, clean up the room/socket mappings so that we can be sure we're
    # clean for broadcast purposes.
    @roomToSockets[room] = _.reject(@roomToSockets[room], (sock) -> sock.sid == socket.sid)
    if @roomToSockets[room].length == 0
      delete @roomToSockets[room]
    @socketIdToRooms[socket.sid] = _.without(@socketIdToRooms[socket.sid], room)
    if @socketIdToRooms[socket.sid].length == 0
      delete @socketIdToRooms[socket.sid]

    # Next, make sure that this socket has a legit session, and announce that
    # the socket has left.
    session_id = @socketIdToSessionId[socket.sid]
    @sessionStore.get session_id, (err, session) =>
      return @handleError(socket, err) if err?

      # 'Last' refers to whether this was the last socket owned by this session
      # that was in this room.
      last = not _.any(@roomToSockets[room], (sock) =>
        @socketIdToSessionId[sock.sid] == session_id
      )
      # Announce to any RoomManager listeners that this socket has left.
      channel = room.split("/")[0]
      emission = {socket, session, room, last}
      @emit "leave", emission
      # Respond to the socket, acknowledging the leave.
      socket_emission = {room, last}
      @socketEmit socket, "leave", socket_emission

  disconnect: (socket) =>
    # Leave all the rooms this socket is in.
    for room in @socketIdToRooms[socket.sid] or []
      # Note: could make this more efficient by getting the session on the
      # outside of the loop, and refactoring @leave to use it.
      @leave(socket, room)

    # Remove the socket/session mapping for this socket.
    session_id = @socketIdToSessionId[socket.sid]
    delete @socketIdToSessionId[socket.sid]
    if session_id?
      @sessionIdToSockets[session_id] = _.reject(@sessionIdToSockets[session_id], (sock) ->
        sock.sid == socket.sid
      )
      if @sessionIdToSockets[session_id].length == 0
        delete @sessionIdToSockets[session_id]

  _getSessionForSocket: (socket, callback) =>
    session_id = @socketIdToSessionId[socket.sid]
    if not session_id?
      return callback("Session not found.")
    @sessionStore.get session_id, (err, session) =>
      return callback(err) if err?
      return callback("Session not found") unless session?
      return callback(null, session)

module.exports = { RoomManager: RoomManager }
