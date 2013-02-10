_             = require 'underscore'
intertwinkles = require './intertwinkles'
RoomManager   = require('iorooms').RoomManager
uuid          = require 'node-uuid'
logger        = require('log4js').getLogger()

build_room_users_list_for_user = (iorooms, user_session, room, callback) ->
  iorooms.getSessionsInRoom room, (err, sessions) ->
    if err? then return callback(err)
    room_list = []
    for session in sessions
      if intertwinkles.is_authenticated(session)
        user = session.users[session.auth.user_id]
        info = { name: user.name, icon: user.icon }
      else
        info = { name: "Anonymous", icon: null }
      info.anon_id = session.anon_id
      room_list.push(info)
    callback(null, { room: room, list: room_list })

route = (config, io, sessionStore) ->
  iorooms = new RoomManager("/io-intertwinkles", io, sessionStore)
  iorooms.authorizeConnection = set_anonymous_id = (session, callback) ->
    if not session.anon_id?
      session.anon_id = uuid.v4()
      iorooms.saveSession(session, callback)
    callback()
  api_methods = require("./api_methods")(config)

  iorooms.onChannel 'verify', (socket, reqdata) ->
    api_methods.authenticate session, reqdata.assertion, (err, session) ->
      iorooms.saveSession session, (err) ->
        return socket.emit "error", {error: err} if err?

        socket.emit reqdata.callback, {
          user_id: session.auth.user_id
          email: session.auth.email
          groups: session.groups
          users: session.users
          message: message
        }

        # Update all room's user lists to include our logged-in name
        rooms = iorooms.sessionRooms[session.sid] or []
        _.each rooms, (room) ->
          build_room_users_list_for_user iorooms, session, room, (err, users) ->
            socket.emit "room_users", users
            socket.broadcast.to(room).emit "room_users", users

        # Join a room for our user ID -- not an iorooms room, a socket.io room
        # for utility broadcasts, without room user menus.
        socket.join(session.auth.user_id)

  iorooms.onChannel "logout", (socket, data) ->
    if intertwinkles.is_authenticated(socket.session)
      # Leave our self-referential utility room.
      socket.leave(socket.session.auth.user_id)

    api_methods.clear_session_auth(socket.session)
    iorooms.saveSession socket.session, ->
      socket.emit(data.callback, {status: "success"})

    # Update all room's user lists to remove our logged-in name
    rooms = iorooms.sessionRooms[socket.session.sid] or []
    _.each rooms, (room) ->
      build_room_users_list_for_user iorooms, session, room, (err, users) ->
        socket.emit "room_users", users
        socket.broadcast.to(room).emit "room_users", users

  iorooms.onChannel "edit_profile", (socket, data) ->
    respond = (err, response) ->
      if err?
        socket.emit data.callback or "error", {error: err}
      else if data.callback?
        socket.emit data.callback, response

    # Must be logged in.
    unless intertwinkles.is_authenticated(socket.session)
      return respond("Not authorized")
    # Edit only yourself.
    if socket.session.auth.email != data.model.email
      return respond("Not authorized")

    api_methods.edit_profile {
      user: socket.session.auth.email,
      name: data.model.name,
      icon_id: data.model.icon.id,
      icon_color: data.model.icon_color,
      mobile_number: data.model.mobile_number,
      mobile_carrier: data.model.mobile_carrier,
    }, (err, doc) ->
      return respond(err) if err?
      socket.session.users[doc.id] = doc
      iorooms.saveSession socket.session, ->
        respond(null, model: doc)

  iorooms.onChannel "get_notifications", (socket, data) ->
    return unless auth.is_authenticated(socket.session)
    api_methods.get_notifications socket.session.auth.email, (err, docs) ->
      return socket.emit "error", {error: err} if err?
      socket.emit "notifications", {notifications: docs}

  iorooms.onChannel "get_short_url", (socket, data) ->
    return unless data.application? and data.path? and data.callback?
    return api_methods.make_short_url data.path, data.application, (err, short_doc) ->
      return socket.emit data.callback, {error: err} if err?
      return socket.emit data.callback, {
        short_url: short_doc.absolute_short_url
        long_url: short_doc.absolute_long_url
      }

  iorooms.on "join", (data) ->
    if err? then return data.socket.emit "error", {error: err}
    session = data.socket.session
    room = data.room
    build_room_users_list_for_user iorooms, session, room, (err, users) ->
      if err? then return data.socket.emit "error", {error: err}
      # inform the client of its anon_id on first join.
      data.socket.emit "room_users", _.extend {
          anon_id: session.anon_id
        }, users
      if data.first
        # Tell everyone else in the room.
        data.socket.broadcast.to(room).emit "room_users", users

  iorooms.on "leave", (data) ->
    return unless data.last
    session = data.socket.session
    room = data.room
    build_room_users_list_for_user iorooms, session, room, (err, users) ->
      if err? then return data.socket.emit "error", {error: err}
      data.socket.broadcast.to(room).emit "room_users", users

module.exports = {
  route
}
