_             = require 'underscore'
async         = require 'async'
express       = require 'express'
RoomManager   = require('iorooms').RoomManager
schema        = require './schema'
intertwinkles = require '../../../lib/intertwinkles'

start = (config, app, io, sessionStore) ->
  iorooms = new RoomManager("/io-clock", io, sessionStore)
  iorooms.authorizeJoinRoom = (seession, name, callback) ->
    schema.ProgTime.findOne {'_id', name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")

  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    intertwinkles.list_accessible_documents schema.ProgTime, req.session, (err, docs) ->
      return res.send(500) if err?
      for doc in docs
        doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      res.render 'clock/index', {
        title: "Progressive Clock"
        initial_data: _.extend(
          {application: "clock", listed_progtimes: docs},
          intertwinkles.get_initial_data(req?.session, config),
          initial_data or {}
        )
        conf: intertwinkles.clean_conf(config)
        flash: req.flash()
      }

  app.get /\/clock$/, (req, res) -> res.redirect "/clock/" # add slash
  app.get '/clock/', (req, res) -> index_res(req, res)

  app.get /\/clock\/c\/([^/]+)$/, (req, res) -> res.redirect "/clock/c/#{req.params[0]}/"
  app.get '/clock/c/:id/', (req, res) ->
    schema.ProgTime.findOne {_id: req.params.id}, (err, doc) ->
      return res.send("Server Error", 500) if err?
      return res.send("Not found", 404) unless doc?
      return res.send("Permission denied", 403) unless intetwinkles.can_view(req.session, doc)
      api_methods.post_event {
        type: "visit"
        application: "clock"
        entity: doc.id
        entity_url: "/clock/c/#{doc.id}/"
        user: req.session.auth?.email
        anon_id: req.session.anon_id
        group: doc.sharing.group_id
        data: { name: doc.name }
      }, 1000 * 60 * 5, (->)

      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      index_res(req, res, {
        progtime: doc.toJSON()
      })

  #
  # Create new prog time
  #

  iorooms.onChannel "create_progtime", (socket, data) ->
    respond = (err, doc) ->
      return socket.emit "error", {error: err} if err?
      doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
      socket.emit "progtime", {progtime: doc, now: new Date()}

    return respond("Missing model attributes") unless data.model?.name?
    return respond("Permission denied") unless intertwinkles.can_edit(data.model) and intertwinkles.can_change_sharing(data.model)

    doc = new schema.ProgTime()
    for key in ["name", "created", "sharing"]
      if data.model[key]?
        doc[key] = data.model[key]
    if data.model?.categories
      doc.categories = []
      for cat in data.model.categories
        doc.categories.push({name: cat.name, times: []})
    doc.save(respond)
  
  #
  # Edit a progtime
  #

  iorooms.onChannel "edit_progtime", (socket, data) ->
    respond = (err, doc) ->
      return socket.emit "error", {error: err} if err?
      doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
      socket.broadcast.to(doc.id).emit "progtime", {progtime: doc, now: new Date()}
      socket.emit "progtime", {progtime: doc, now: new Date()}

    unless data.model?._id
      return respond("Missing progtime id")

    updates = {}
    changes = false
    for key in ["name", "sharing", "categories"]
      if data.model[key]?
        updates[key] = data.model[key]
        changes = true

    if not changes then return socket.emit "error", {error: "No edits specified."}

    schema.ProgTime.findOne {_id: data.model._id}, (err, doc) ->
      return respond("Server error") if err?
      return respond("Not found") unless doc?
      return respond("Permission denied") unless intertwinkles.can_edit(req.session, doc)
      if updates.sharing and not intertwinkles.can_change_sharing(req.session, doc)
        return respond("Permission denied")

      doc.name = updates.name if updates.name
      doc.sharing = updates.sharing if updates.sharing
      if updates.categories
        for cat,i in updates.categories
          if i < doc.categories.length
            doc.categories[i].name = cat.name
          else
            doc.categories.push({name: cat.name, times: []})
        doc.categories = _.filter(doc.categories, (c) -> !!c.name)

      # Make sure we can still change sharing after changes have been applied.
      # (e.g. protect the new sharing values)
      unless intertwinkles.can_change_sharing(req.session, doc)
        return respond("Permission denied")
      doc.save(respond)
  
  #
  # Start and stop timers
  #

  iorooms.onChannel "update_time", (socket, data) ->
    respond = (err, doc, dont_rebroadcast) ->
      return socket.emit "error", {error: err} if err?
      doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
      emission = {
        _id: doc.id
        category: doc.categories[data.category]
        now: new Date()
      }
      unless dont_rebroadcast
        socket.broadcast.to(doc.id).emit "progtime", emission
      socket.emit "category", emission

    schema.ProgTime.findOne {_id: data._id}, (err, doc) ->
      return respond("Server error") if err?
      return respond("Not found") unless doc?
      return respond("Permission denied") unless intertwinkles.can_edit(req.session, doc)
      return respond("Category not found") unless doc.categories[data.category]?

      now = new Date()
      cat = doc.categories[data.category]
      # Ignore the request to start if there is an open entry.
      if data.start and (cat.times.length == 0 or cat.times[cat.times.length - 1].stop)
        cat.times.push({start: now, stop: null})
      # Ignore the request to stop if there is no open entry.
      else if data.stop and cat.times.length > 0 and not cat.times[cat.times.length - 1].stop
        cat.times[cat.times.length - 1].stop = now
      else
        # No action to perform.
        return respond(null, doc, true)
      # Action taken, save and respond.
      return doc.save(respond)

module.exports = { start }
