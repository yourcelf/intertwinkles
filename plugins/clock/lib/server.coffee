_             = require 'underscore'
utils         = require '../../../lib/utils'

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  clock = require('./clock')(config)

  sockrooms.addChannelAuth "clock", (session, room, callback) ->
    name = room.split("/")[1]
    schema.Clock.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("Clock #{name} not found") unless doc?
      return callback(null, utils.can_view(session, doc))
  
  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    utils.list_accessible_documents schema.Clock, req.session, (err, docs) ->
      return www_methods.handle_error(req, res, err) if err?
      for doc in docs
        doc.sharing = utils.clean_sharing(req.session, doc)
      res.render 'clock/index', {
        title: "Progressive Clock"
        initial_data: _.extend(
          {application: "clock", clock_list: docs},
          utils.get_initial_data(req?.session, config),
          initial_data or {}
        )
        conf: utils.clean_conf(config)
        flash: req.flash()
      }

  utils.append_slash(app, "/clock")
  app.get '/clock/', (req, res) ->
    index_res(req, res)

  utils.append_slash(app, "/clock/add")
  app.get '/clock/add/', (req, res) -> index_res(req, res)
  utils.append_slash(app, "/clock/about")
  app.get '/clock/about/', (req, res) -> index_res(req, res)

  utils.append_slash(app, "/clock/c/.*[^/]$")
  app.get '/clock/c/:id/:tag?/', (req, res) ->
    schema.Clock.findOne {_id: req.params.id}, (err, doc) ->
      if err? and err.name != "CastError"
        return www_methods.handle_error(req, res, err)
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        if utils.is_authenticated(req.session)
          return www_methods.permission_denied(req, res)
        else
          return www_methods.redirect_to_login(req, res)

      clock.post_event req.session, doc, {type: "visit"}, 5 * 60 * 1000, ->
        doc.sharing = utils.clean_sharing(req.session, doc)
        index_res(req, res, { clock: doc.toJSON() })

  #
  # Socket routes
  #

  sockrooms.on "clock/fetch_clock_list", (socket, session, data) ->
    clock.fetch_clock_list session, (err, docs) ->
      for doc in data.group or []
        doc.sharing = utils.clean_sharing(session, doc)
      for doc in data.public or []
        doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON "error", {error: err} if err?
      return socket.sendJSON "clock_list", docs

  sockrooms.on "clock/fetch_clock", (socket, session, data) ->
    clock.fetch_clock data?._id, session, (err, doc) ->
      return socket.sendJSON("error", {error: err}) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON(data.callback or "clock", {
        model: doc
        now: new Date()
      })

  sockrooms.on "clock/save_clock", (socket, session, data) ->
    clock.save_clock session, data, (err, doc) ->
      return socket.sendJSON("error", {error: err}) if err?
      orig_sharing = doc.sharing
      # We want a different sharing cleaning, potentially, for each room
      # member.
      # First, send to the saver, who may not be in the room yet if this is a
      # new clock.
      doc.sharing = utils.clean_sharing(session, doc)
      socket.sendJSON data.callback or "clock", {model: doc}
      # Next, send to anyone who is in the room.
      sockrooms.roomSocketSessionMap "clock/#{doc.id}", (err, socket, sess) ->
        return logger.error(err) if err?
        if sess.session_id != session.session_id
          doc.sharing = utils.clean_sharing(sess, {sharing: orig_sharing})
          socket.sendJSON "clock", {model: doc}

  sockrooms.on "clock/set_time", (socket, session, data) ->
    clock.set_time session, data, (err, doc) ->
      return socket.sendJSON("clock", {model:doc}) if err == "Out of sync"
      return socket.sendJSON("error", {error: err}) if err?
      sockrooms.broadcast("clock/#{doc.id}", "clock:time", {
        category: data.category
        time: data.time
        index: data.index
        now: new Date()
      })

module.exports = { start }
