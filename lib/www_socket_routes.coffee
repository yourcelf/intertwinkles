###
Defines the set of base routes for websocket messages:
 - verify (authenticating)
 - logout (unauthenticating)
 - get_notifications (request for a list of current notifications)
 - get_short_url (request for a short URL for a particular app)
 - join (request to join a broadcast room; see lib/socket_server)
 - leave (request to leave a broadcast room; see lib/socket_server)
 - edit_profile (request to change profile details)

This module is the counterpart to `lib/www_routes` which handles HTTP routing
for these basic functions. All data/state modification should take place in
`lib/www_methods` or `lib/api_methods`.
###
_             = require 'underscore'
utils         = require './utils'
uuid          = require 'node-uuid'
logger        = require('log4js').getLogger()

build_room_users_list_for_user = (sockrooms, user_session, room, callback) ->
  sockrooms.getSessionsInRoom room, (err, sessions) ->
    if err? then return callback(err)
    room_list = []
    for session in sessions
      continue unless session?
      if utils.is_authenticated(session)
        user = session.users[session.auth.user_id]
        info = { name: user.name, icon: user.icon }
      else
        info = { name: "Anonymous", icon: null }
      info.anon_id = session.anon_id
      room_list.push(info)
    callback(null, { room: room, list: room_list })

route = (config, sockrooms) ->
  api_methods = require("./api_methods")(config)
  email_notices = require("./email_notices").load(config)

  sockrooms.on 'verify', (socket, session, reqdata) ->
    forceLogout = (err) ->
      sockrooms.handleError(socket, err)
      socket.sendJSON("force_logout")

    api_methods.authenticate session, reqdata.assertion, (err, session, message) ->
      return forceLogout(err) if err?
      sockrooms.saveSession session, (err) ->
        return forceLogout(err) if err?

        socket.sendJSON(reqdata.callback, {
          user_id: session.auth.user_id
          email: session.auth.email
          groups: session.groups
          users: session.users
          message: message
        })

        # Update all room's user lists to include our logged-in name
        rooms = sockrooms.getRoomsForSessionId(session.session_id)
        _.each rooms, (room) ->
          build_room_users_list_for_user sockrooms, session, room, (err, users) ->
            socket.sendJSON "room_users", users
            sockrooms.broadcast(room, "room_users", users, socket.sid)

        sockrooms.joinWithoutAuth socket, session, session.auth.user_id, {silent: true}

  sockrooms.on "logout", (socket, session, data) ->
    if utils.is_authenticated(session)
      # Leave our self-referential utility room.
      sockrooms.leave(socket, session.auth.user_id)

    api_methods.clear_session_auth(session)
    sockrooms.saveSession session, ->
      socket.sendJSON(data.callback, {status: "success"})

    # Update all room's user lists to remove our logged-in name
    rooms = sockrooms.getRoomsForSessionId(session.session_id)
    _.each rooms, (room) ->
      build_room_users_list_for_user sockrooms, session, room, (err, users) ->
        socket.sendJSON "room_users", users
        sockrooms.broadcast(room, "room_users", users, socket.sid)

  sockrooms.on "edit_profile", (socket, session, data) ->
    respond = (err, response) ->
      if err?
        socket.sendJSON data.callback or "error", {error: err}
      else if data.callback?
        socket.sendJSON data.callback, response

    # Must be logged in.
    unless utils.is_authenticated(session)
      return respond("Not authorized")
    # Edit only yourself.
    if session.auth.email != data.model.email
      return respond("Not authorized")

    api_methods.edit_profile {
      user: session.auth.email,
      name: data.model.name,
      icon_id: data.model.icon.id,
      icon_color: data.model.icon.color,
      mobile_number: data.model.mobile_number,
      mobile_carrier: data.model.mobile_carrier,
    }, (err, doc) ->
      return respond(err) if err?
      session.users[doc.id] = doc
      sockrooms.saveSession session, ->
        respond(null, model: doc)

  sockrooms.on "get_notifications", (socket, session, data) ->
    return unless utils.is_authenticated(session)
    api_methods.get_notifications session.auth.email, (err, docs) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON "notifications", {notifications: docs}

  sockrooms.on "get_short_url", (socket, session, data) ->
    return unless data.application? and data.path? and data.callback?
    return api_methods.make_short_url data.path, data.application, (err, short_doc) ->
      return socket.sendJSON data.callback, {error: err} if err?
      return socket.sendJSON data.callback, {
        short_url: short_doc.absolute_short_url
        long_url: short_doc.absolute_long_url
      }

  sockrooms.on "stats", (socket, session, data) ->
    return socket.sendJSON "stats", {
      count: _.size(sockrooms.sessionIdToSockets)
    }

  sockrooms.on "email_group", (socket, session, data) ->
    email_notices.send_custom_group_message session, data, (err) ->
      return sockrooms.handle_error(socket, err) if err?
      socket.sendJSON "email_sent", {}

  sockrooms.on "join", (data) ->
    {socket, session, room, first} = data
    build_room_users_list_for_user sockrooms, session, room, (err, users) ->
      return sockrooms.handleError(socket, err) if err?
      # inform the client of its anon_id on first join.
      socket.sendJSON "room_users", _.extend {
          anon_id: session.anon_id
        }, users
      if first
        # Tell everyone else in the room.
        sockrooms.broadcast room, "room_users", users, socket.sid

  sockrooms.on "leave", (data) ->
    {socket, session, room, last} = data
    return unless last
    build_room_users_list_for_user sockrooms, session, room, (err, users) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast room, "room_users", users

module.exports = {
  route
}
