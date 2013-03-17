_             = require 'underscore'
async         = require 'async'
express       = require 'express'
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
      return res.status(500).send("server error") if err?
      for doc in docs
        doc.sharing = utils.clean_sharing(req.session, doc)
      res.render 'clock/index', {
        title: "Progressive Clock"
        initial_data: _.extend(
          {application: "clock", listed_progtimes: docs},
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
  app.get '/clock/c/:id/', (req, res) ->
    schema.Clock.findOne {_id: req.params.id}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        if utils.is_authenticated(req.session)
          return www_methods.permission_denied(req, res)
        else
          return www_methods.redirect_to_login(req, res)

      clock.post_event req.ession, doc, "visit", ->
        doc.sharing = utils.clean_sharing(req.session, doc)
        index_res(req, res, { clock: doc.toJSON() })

  #
  # Socket routes
  #

  sockrooms.on "clock/fetch_clock_list", (socket, session, data) ->
    utils.list_accessible_documents schema.Clock, session, (err, docs) ->
      for doc in docs.group
        doc.sharing = utils.clean_sharing(doc)
      for doc in docs.public
        doc.sharing = utils.clean_sharing(doc)
      socket.emit "clock_list", docs

  sockrooms.on "clock/fetch_clock", (socket, session, data) ->
    schema.Clock.findOne {_id: data._id}, (err, doc) ->
      unless utils.can_view(session, doc)
        return socket.sendJSON "error", {error: "Permission denied"}
      unless doc?
        return socket.sendJSON "error", {error: "Clock #{data._id} not found."}
      doc.sharing = utils.clean_sharing(doc)
      socket.sendJSON data.callback or "clock", { model: doc }

  sockrooms.on "clock/save_clock", (socket, session, data) ->
    unless data?.model
      return socket.sendJSON "error", {error: "Missing model param"}
    schema.Clock.findOne {_id: data.model?._id}, (err, doc) ->
      unless utils.can_edit(session, doc)
        return socket.sendJSON "error", {error: "Permission denied"}
      unless doc
        doc = new schema.Clock()
      unless utils.can_change_sharing(session, doc)
        delete data.model?.sharing
      for key in ["name", "sharing", "present", "categories"]
        if data.model[key]?
          doc[key] = data.model[key]
      doc.save (err, doc) ->
        return socket.sendJSON "error", {error: err} if err?
        doc.sharing = utils.clean_sharing(doc)
        socket.sendJSON data.callback or "clock", {model: doc}
        sockrooms.broadcast("clock/#{doc.id}", "clock", {model: doc}, socket.sid)

  sockrooms.on "clock/set_time", (socket, session, data) ->
    for key in ["_id", "category", "time", "index", "now"]
      unless data[key]?
        return socket.sendJSON "error", {error: "Missing param #{key}"}
    schema.Clock.findOne {_id: data._id}, (err, doc) ->
      return socket.sendJSON "error", {error: err} if err?
      return socket.sendJSON "error", {error: "Not found"} unless doc?
      unless utils.can_edit(session, doc)
        return socket.sendJSON "error", {error: "Permission denied"}
      category = doc.categories[data.category]
      unless category? and (
          (data.index == category.times.length and not data.time.stop) or
          (data.index == category.times.length - 1 and data.time.stop))
        # Just send the clock instead; they're out of sync.
        doc.sharing = utils.clean_sharing(doc)
        return socket.sendJSON "clock", {model: doc}
      #XXX: How to manage client clock skew? Do we trust them to do so?
      if data.index == category.times.length
        category.times.push(data.time)
      else
        category.times[data.index] = data.time
      sockrooms.broadcast("clock/#{doc.id}", "clock:time", {
        category: data.category
        time: data.time
        index: data.index
        now: new Date()
      })

module.exports = { start }
