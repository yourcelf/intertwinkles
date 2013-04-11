express       = require 'express'
_             = require 'underscore'
async         = require 'async'
utils         = require '../../../lib/utils'
logger        = require('log4js').getLogger("firestarter")

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  api_methods = require("../../../lib/api_methods")(config)
  fslib = require("./firestarter")(config)

  sockrooms.addChannelAuth "firestarter", (session, room, callback) ->
    name = room.split("/")[1]
    # Only allow to join the room if we're allowed to view the firestarter.
    schema.Firestarter.findOne {'slug': name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if utils.can_view(session, doc)
        callback(null, true)
      else
        callback(null, false)

  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    utils.list_accessible_documents schema.Firestarter, req.session, (err, docs) ->
      return www_methods.handle_error(req, res, err) if err?
      res.render 'firestarter/index', {
        title: "Firestarter"
        initial_data: _.extend(
          {application: "firestarter"},
          utils.get_initial_data(req.session, config), {
            listed_firestarters: docs
          }, initial_data)
        conf: utils.clean_conf(config)
        flash: req.flash()
      }

  utils.append_slash(app, "/firestarter")
  app.get '/firestarter/', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/new', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/f/:slug', (req, res) ->
    fslib.get_firestarter req.session, {slug: req.params.slug}, (err, doc) ->
      if err == "Permission denied"
        return www_methods.redirect_to_login(req, res)
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      doc.sharing = utils.clean_sharing(req.session, doc)
      index_res(req, res, {firestarter: doc.toJSON()})

  #
  # Get a valid slug for a firestarter that hasn't yet been used.
  #
  sockrooms.on "firestarter/get_unused_slug", (socket, session, data) ->
    return sockrooms.handleError(socket, "Missing callback") unless data.callback?
    fslib.get_unused_slug (err, slug) ->
      return sockrooms.handleError(socket, err) if err?
      return socket.sendJSON(data.callback, {slug: slug})

  #
  # Create a new firestarter.
  #
  sockrooms.on "firestarter/create_firestarter", (socket, session, data) ->
    unless data.callback?
      return sockrooms.handleError(socket, "Missing callback")
    unless data.model?
      return sockrooms.handleError(socket, "Missing model")
    fslib.create_firestarter session, data.model, (err, doc, event, si) ->
      if err == "ValidationError"
        # 'doc' will be an array of errors
        socket.sendJSON(data.callback, {error: doc, type: err})
      else if err?
        sockrooms.handleError(socket, err)
      else
        socket.sendJSON(data.callback, {model: doc.toJSON()})

  #
  # Edit a firestarter
  #
  sockrooms.on 'firestarter/edit_firestarter', (socket, session, data) ->
    fslib.edit_firestarter session, data.model, (err, doc, event, si) ->
      return socketrooms.handleError(socket, err) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      res = {model: doc.toJSON()}
      delete res.model.responses
      if data.callback? then socket.sendJSON(data.callback, res)
      sockrooms.broadcast("firestarter/" + doc.slug,
        "firestarter", res, socket.sid)

  #
  # Retrieve a firestarter with responses.
  #
  sockrooms.on 'firestarter/get_firestarter', (socket, session, data) ->
    return sockrooms.handleError(socket, "Missing slug") unless data.slug?
    fslib.get_firestarter session, {slug: data.slug}, (err, doc, event) ->
      return sockrooms.handleError(socket, err) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      socket.sendJSON("firestarter", {model: doc})

  #
  # Get a list of available firestarters
  #
  sockrooms.on "firestarter/get_firestarter_list", (socket, session, data) ->
    if not data.callback?
      sockrooms.handleError(socket, "Missing callback parameter.")
    else
      utils.list_accessible_documents(
        schema.Firestarter, session, (err, docs) ->
          return socket_error(socket, err) if err?
          for doc in docs.group
            doc.sharing = utils.clean_sharing(session, doc)
          for doc in docs.public
            doc.sharing = utils.clean_sharing(session, doc)
          socket.sendJSON data.callback, {docs: docs}
      )

  #
  # Get a list of events.
  #
  sockrooms.on "firestarter/get_firestarter_events", (socket, session, data) ->
    unless data.firestarter_id?
      return sockrooms.handleError(socket, "Missing firestarter ID")
    unless data.callback?
      return sockrooms.handleError(socket, "Missing callback")
    schema.Firestarter.findOne {_id: data.firestarter_id}, 'sharing', (err, doc) ->
      if not utils.can_view(session, doc)
        return sockrooms.handleError(socket, "Permission denied")
      api_methods.get_events {
        application: "firestarter"
        entity: doc.id
      }, (err, events) ->
        return socket_error(socket, err) if err?
        socket.sendJSON data.callback, {events: events}


  #
  # Save a response to a firestarter.
  #
  sockrooms.on "firestarter/save_response", (socket, session, data) ->
    fslib.save_response session, data.model, (err, firestarter, new_response) ->
      return sockrooms.handleError(socket, err) if err?
      responseData = {model: new_response.toJSON()}
      sockrooms.broadcast("firestarter/" + firestarter.slug,
        "response",
        responseData,
        socket.sid)
      socket.sendJSON(data.callback, responseData) if data.callback?

  #
  # Delete a response
  #
  sockrooms.on "firestarter/delete_response", (socket, session, data) ->
    unless data.model?._id? and data.model.firestarter_id? and data.callback?
      return sockrooms.handleError(socket,
        "Missing params _id, firestarter_id, or callback")
    fslib.delete_response session, data.model, (err, firestarter, deleted_response) ->
      return sockrooms.handleError(socket, err) if err?
      responseData = {model: deleted_response.toJSON()}
      socket.sendJSON(data.callback, responseData)
      sockrooms.broadcast("firestarter/" + firestarter.slug,
        "delete_response",
        responseData,
        socket.sid)

  return { app }

module.exports = { start }
