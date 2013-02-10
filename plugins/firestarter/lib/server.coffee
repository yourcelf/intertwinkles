express       = require 'express'
RoomManager   = require('iorooms').RoomManager
schema        = require './schema'
_             = require 'underscore'
async         = require 'async'
intertwinkles = require '../../../lib/intertwinkles'

start = (config, app, io, sessionStore) ->
  io.of("/io-firestarter").setMaxListeners(15)
  iorooms = new RoomManager("/io-firestarter", io, sessionStore)
  iorooms.authorizeJoinRoom = (session, name, callback) ->
    # Only allow to join the room if we're allowed to view the firestarter.
    schema.Firestarter.findOne {'slug': name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")

  api_methods = require("../../../lib/api_methods")(config)

  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    intertwinkles.list_accessible_documents schema.Firestarter, req.session, (err, docs) ->
      return res.send(500) if err?
      res.render 'firestarter/index', {
        title: "Firestarter"
        initial_data: _.extend(
          {application: "firestarter"},
          intertwinkles.get_initial_data(req.session, config), {
            listed_firestarters: docs
          }, initial_data)
        conf: intertwinkles.clean_conf(config)
        flash: req.flash()
      }

  app.get /\/firestarter$/, (req, res) -> res.redirect('/firestarter/')
  app.get '/firestarter/', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/new', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/f/:slug', (req, res) ->
    schema.Firestarter.with_responses {slug: req.params.slug}, (err, doc) ->
      return res.send(500) if err?
      return res.send(404) if not doc?
      #FIXME: Redirect to login instead.
      return res.send(403) if not intertwinkles.can_view(req.session, doc)

      api_methods.post_event {
        type: "visit"
        application: "firestarter"
        entity: doc.id
        entity_url: "/firestarter/f/#{doc.slug}"
        user: req.session.auth?.email
        anon_id: req.session.anon_id
        group: doc.sharing.group_id
        data: {
          title: doc.name
        }
      }, 5000 * 60, (->)

      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      index_res(req, res, {
        firestarter: doc.toJSON()
      })

  # Get a valid slug for a firestarter that hasn't yet been used.
  iorooms.onChannel 'get_unused_slug', (socket, data) ->
    choices = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    unless data.callback?
      socket.emit("error", {error: "Must specify callback."})
      return

    get_slug = ->
      random_name = (
        choices.substr(parseInt(Math.random() * choices.length), 1) for i in [0...6]
      ).join("")
      schema.Firestarter.find {slug: random_name}, (err, things) ->
        socket.emit({error: err}) if err
        if things.length == 0
          socket.emit(data.callback, {slug: random_name})
        else
          get_slug()
    get_slug()

  # Create a new firestarter.
  iorooms.onChannel "create_firestarter", (socket, data) ->
    unless data.callback?
      return socket.emit("error", {error: "Must specifiy callback."})
    unless data.model?
      return socket.emit("error", {error: "Missing required model attribute."})
    unless intertwinkles.can_edit(socket.session, data.model)
      return socket.emit("error", {error: "Permission denied"})

    model = new schema.Firestarter(data.model)
    model.save (err, model) ->
      if err?
        errors = []
        if err.name == "ValidationError"
          for field, error of err.errors
            if error.type == "required"
              errors.push({field: field, message: "This field is required."})
            else
              errors.push({field: field, message: error.message})
          socket.emit(data.callback, {error: errors, type: "ValidationError"})
        else if err.name == "MongoError" and err.err.indexOf("duplicate key") != -1
          errors.push({field: "slug", message: "This name is already taken."})
          socket.emit(data.callback, {error: errors, type: "ValidationError"})
        else
          socket.emit(data.callback, {error: []})
      else
        socket.emit(data.callback, {model: model.toJSON()})
        url = "/firestarter/f/#{model.slug}"
        api_methods.post_event {
          type: "create"
          application: "firestarter"
          entity: model.id
          entity_url: url
          user: socket.session.auth?.email
          anon_id: socket.session.anon_id
          group: model.sharing.group_id
          data: {
            action: {
              name: model.name
              prompt: model.prompt
            }
            title: model.name
          }
        }, (->)
        api_methods.add_search_index {
          application: "firestarter"
          entity: model.id
          type: "firestarter"
          url: url
          title: model.name
          summary: model.prompt
          text: [model.name, model.prompt].join("\n")
          sharing: model.sharing
        }

  # Edit a firestarter
  iorooms.onChannel 'edit_firestarter', (socket, data) ->
    updates = {}
    changes = false
    for key in ["name", "prompt", "public", "sharing"]
      if data.model?[key]
        updates[key] = data.model[key]
        changes = true
    if not changes then return socket.emit "error", {error: "No edits specified."}

    schema.Firestarter.findOne({
      _id: data.model._id
    }).populate('responses').exec (err, doc) ->
      if err? then return socket.emit "error", {error: err}
      unless intertwinkles.can_edit(socket.session, doc)
        return socket.emit("error", {error: "Permission denied"})
      unless intertwinkles.can_change_sharing(socket.session, doc)
        delete updates.sharing
      for key, val of updates
        doc[key] = val
      doc.save (err, doc) ->
        if err? then return socket.emit "error", {error: err}
        doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
        res = {model: doc.toJSON()}
        delete res.model.responses
        if data.callback? then socket.emit data.callback, res
        socket.broadcast.to(doc.slug).emit "firestarter", res
        
        # Add event and search index.
        url = "/firestarter/f/#{doc.slug}"
        api_methods.post_event {
          type: "update"
          application: "firestarter"
          entity: doc.id
          entity_url: url
          user: socket.session.auth?.email
          anon_id: socket.session.anon_id
          group: doc.sharing.group_id
          data: {
            title: doc.name
            action: updates
          }
        }, (->)
        api_methods.add_search_index({
          application: "firestarter"
          entity: doc.id
          type: "firestarter"
          url: url
          title: doc.name
          summary: doc.prompt
          sharing: doc.sharing
          text: [doc.name, doc.prompt].concat((
            res.response for res in doc.responses
          )).join("\n")
        })

  # Retrieve a firestarter with responses.
  iorooms.onChannel 'get_firestarter', (socket, data) ->
    unless data.slug?
      socket.emit("error", {error: "Missing slug!"})
    schema.Firestarter.with_responses {slug: data.slug}, (err, model) ->
      if err?
        socket.emit("error", {error: err})
      else if not model?
        socket.emit("firestarter", {error: 404})
      else if not intertwinkles.can_view(socket.session, model)
        socket.emit("error", {error: "Permission denied"})
      else
        model.sharing = intertwinkles.clean_sharing(socket.session, model)
        socket.emit("firestarter", {
          model: model.toJSON()
        })
        api_methods.post_event {
          type: "visit"
          application: "firestarter"
          entity: model.id
          entity_url: "/firestarter/f/#{model.slug}"
          user: socket.session.auth?.email
          anon_id: socket.session.anon_id
          group: model.sharing.group_id
          data: { title: model.name }
        }, 5000 * 60, (->)
  
  iorooms.onChannel "get_firestarter_list", (socket, data) ->
    if not data.callback?
      socket.emit "error", {error: "Missing callback parameter."}
    else
      intertwinkles.list_accessible_documents(
        schema.Firestarter, socket.session, (err, docs) ->
          if err? then return socket.emit data.callback, {error: err}
          socket.emit data.callback, {docs: docs}
      )

  iorooms.onChannel "get_firestarter_events", (socket, data) ->
    unless data.firestarter_id?
      return socket.emit "error", {error: "Missing firestarter ID"}
    unless data.callback?
      return socket.emit "error", {error: "Missing callback"}
    schema.Firestarter.findOne {_id: data.firestarter_id}, (err, doc) ->
      if not intertwinkles.can_view(socket.session, doc)
        return socket.emit "error", {error: "Permission denied"}
      api_methods.get_events {
        application: "firestarter"
        entity: doc.id
      }, (err, events) ->
        return socket.emit "error", {error: err} if err?
        socket.emit data.callback, {events: events}

  # Save a response to a firestarter.
  iorooms.onChannel "save_response", (socket, data) ->
    async.waterfall [
      # Grab the firestarter. Populate responses so we can build search
      # content.
      (done) ->
        schema.Firestarter.findOne({
          _id: data.model.firestarter_id
        }).populate("responses").exec (err, firestarter) ->
          return done(err) if err?
          unless intertwinkles.can_edit(socket.session, firestarter)
            done("Permission denied")
          else
            done(null, firestarter)

      # Save the response.
      (firestarter, done) ->
        updates = {
          user_id: data.model.user_id
          name: data.model.name
          response: data.model.response
          firestarter_id: firestarter._id
        }
        if data.model._id
          conditions = {
            _id: data.model._id
          }
          options = {upsert: true, 'new': true}
          schema.Response.findOneAndUpdate conditions, updates, options, (err, doc) ->
            done(err, firestarter, doc)
        else
          new schema.Response(updates).save (err, doc) ->
            done(err, firestarter, doc)

      # Replace or insert the response, build search content
      (firestarter, response, done) ->
        found = false
        for orig_response,i in firestarter.responses
          if orig_response._id == response._id
            firestarter.responses.splice(i, 1, response)
            found = true
            break
        if not found
          firestarter.responses.push(response)

        # Get the search content.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in firestarter.responses
        )).join("\n")

        # If this is a new response, un-populate responses and save it to
        # the firestarter's list.
        if not found
          firestarter.save (err, doc) ->
            done(err, doc, response, search_content)
        else
          done(err, firestarter, response, search_content)

    ], (err, firestarter, response, search_content) ->
      # Call back to sockets.
      return socket.emit "error", {error: err} if err?
      responseData = {model: response.toJSON()}
      socket.broadcast.to(firestarter.slug).emit("response", responseData)
      socket.emit(data.callback, responseData) if data.callback?

      # Post search data
      url = "/firestarter/f/#{firestarter.slug}"
      api_methods.add_search_index {
        application: "firestarter", entity: firestarter.id,
        type: "firestarter", url: url,
        title: firestarter.name, summary: firestarter.prompt,
        sharing: firestarter.sharing
        text: search_content
      }, (err) ->
        socket.emit("error", {error: err}) if err?

      # Post an event if we're signed in.
      api_methods.post_event {
        type: "append"
        application: "firestarter"
        entity: firestarter.id
        entity_url: url
        user: response.user_id or null
        anon_id: socket.session.anon_id
        via_user: socket.session.auth?.user_id
        group: firestarter.sharing.group_id
        data: {
          title: firestarter.name
          action: response.toJSON()
        }
      }, (->)

  # Delete a response
  iorooms.onChannel "delete_response", (socket, data) ->
    return done("No response._id specified") unless data.model._id?
    return done("No firestarter_id specified") unless data.model.firestarter_id?
    async.waterfall [
      (done) ->
        # Fetch firestarter and validate permissions.
        schema.Firestarter.findOne({
          _id: data.model.firestarter_id
          responses: data.model._id
        }).populate('responses').exec (err, firestarter) ->
          return done(err) if err?
          return done("Firestarter not found.") unless firestarter?
          unless intertwinkles.can_edit(socket.session, firestarter)
            return done("Permission denied")
          
          for response,i in firestarter.responses
            if response._id.toString() == data.model._id
              firestarter.responses.splice(i, 1)
              return done(null, firestarter, response)
          return done("Error: response not found")

      (firestarter, response, done) ->
        # Build search content, save firestarter and response.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in firestarter.responses
        )).join("\n")
        async.parallel [
          (done) -> firestarter.save(done)
          (done) -> response.remove(done)
        ], (err) ->
          done(err, firestarter, response, search_content)

      (firestarter, response, search_content, done) ->
        # Respond to the sockets
        responseData = {model: {_id: data.model._id}}
        socket.emit(data.callback, responseData) if data.callback?
        socket.broadcast.to(firestarter.slug).emit("delete_response", responseData)

        # Post event
        url = "/firestarter/f/#{firestarter.slug}"
        api_methods.post_event {
          type: "trim"
          application: "firestarter"
          entity: firestarter.id
          entity_url: url
          user: socket.session.auth?.email
          anon_id: socket.session.anon_id
          group: firestarter.sharing.group_id
          data: {
            title: firestarter.name
            action: response?.toJSON()
          }
        }, (err) ->
          socket.emit "error", {error: err} if err?
        
        # Post search index
        api_methods.add_search_index {
            application: "firestarter", entity: firestarter.id,
            type: "firestarter", url: url,
            title: firestarter.name, summary: firestarter.prompt,
            text: search_content, sharing: firestarter.sharing,
          }, (err) ->
            socket.emit "error", {error: err} if err?

    ], (err) ->
      socket.emit "error", {error: err} if err?

  return { app, io, iorooms, sessionStore }

module.exports = { start }
