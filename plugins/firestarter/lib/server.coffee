express       = require 'express'
_             = require 'underscore'
async         = require 'async'
utils         = require '../../../lib/utils'
logger        = require('log4js').getLogger("firestarter")

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)

  sockrooms.addChannelAuth "firestarter", (session, room, callback) ->
    name = room.split("/")[1]
    # Only allow to join the room if we're allowed to view the firestarter.
    schema.Firestarter.findOne {'slug': name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if utils.can_view(session, doc)
        callback(null, true)
      else
        callback(null, false)

  api_methods = require("../../../lib/api_methods")(config)

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

  app.get /\/firestarter$/, (req, res) -> res.redirect('/firestarter/')
  app.get '/firestarter/', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/new', (req, res) -> index_res(req, res, {})
  app.get '/firestarter/f/:slug', (req, res) ->
    schema.Firestarter.with_responses {slug: req.params.slug}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      #FIXME: Redirect to login instead.
      return www_methods.redirect_to_login(req, res) if not utils.can_view(req.session, doc)

      api_methods.post_event {
        type: "visit"
        application: "firestarter"
        entity: doc.id
        entity_url: "/f/#{doc.slug}"
        user: req.session.auth?.email
        anon_id: req.session.anon_id
        group: doc.sharing.group_id
        data: {
          title: doc.name
        }
      }, 5000 * 60, (err) -> return socket_error(socket, err) if err?

      doc.sharing = utils.clean_sharing(req.session, doc)
      index_res(req, res, {
        firestarter: doc.toJSON()
      })
  #
  # Socket errors
  #
  socket_error = (socket, err) ->
    logger.error(err)
    socket.sendJSON "error", {error: err}
  #
  # Add an event entry for the given firestarter.
  #
  add_firestarter_event = (firestarter, event_params, timeout, callback=(->)) ->
    for key in ["type", "anon_id", "data"]
      if not event_params[key]?
        return callback("Missing event param #{key}")

    event_data = _.extend({
      application: "firestarter"
      entity: firestarter.id
      entity_url: "/f/#{firestarter.slug}"
      group: firestarter.sharing.group_id
    }, event_params)

    api_methods.post_event(event_data, timeout, callback)

  #
  # Add or update the search index for the given firestarter.
  #
  add_firestarter_search = (firestarter, responses, callback) ->
    callback or= (->)
    # Post search content
    search_content = [firestarter.name, firestarter.prompt].concat(
      (r.response for r in responses)
    ).join("\n")
    api_methods.add_search_index({
      application: "firestarter"
      entity: firestarter.id
      type: "firestarter"
      url: "/f/#{firestarter.slug}"
      title: firestarter.name
      summary: firestarter.prompt
      text: search_content
      sharing: firestarter.sharing
    }, callback)

  #
  # Get a valid slug for a firestarter that hasn't yet been used.
  #
  sockrooms.on "firestarter/get_unused_slug", (socket, session, data) ->
    choices = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    unless data.callback?
      socket.sendJSON("error", {error: "Must specify callback."})
      return

    get_slug = ->
      random_name = (
        choices.substr(parseInt(Math.random() * choices.length), 1) for i in [0...6]
      ).join("")
      schema.Firestarter.find {slug: random_name}, (err, things) ->
        socket.sendJSON({error: err}) if err
        if things.length == 0
          socket.sendJSON(data.callback, {slug: random_name})
        else
          get_slug()
    get_slug()

  #
  # Create a new firestarter.
  #
  sockrooms.on "firestarter/create_firestarter", (socket, session, data) ->
    unless data.callback?
      return socket.sendJSON("error", {error: "Must specifiy callback."})
    unless data.model?
      return socket.sendJSON("error", {error: "Missing required model attribute."})
    unless utils.can_edit(session, data.model)
      return socket.sendJSON("error", {error: "Permission denied"})

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
          socket.sendJSON(data.callback, {error: errors, type: "ValidationError"})
        else if err.name == "MongoError" and err.err.indexOf("duplicate key") != -1
          errors.push({field: "slug", message: "This name is already taken."})
          socket.sendJSON(data.callback, {error: errors, type: "ValidationError"})
        else
          socket.sendJSON(data.callback, {error: []})
      else
        socket.sendJSON(data.callback, {model: model.toJSON()})
        add_firestarter_event(model, {
          type: "create"
          user: session.auth?.email
          anon_id: session.anon_id
          data: { action: { name: model.name, prompt: model.prompt } }
        }, 0)
        add_firestarter_search(model, [])

  #
  # Edit a firestarter
  #
  sockrooms.on 'firestarter/edit_firestarter', (socket, session, data) ->
    updates = {}
    changes = false
    for key in ["name", "prompt", "public", "sharing"]
      if data.model?[key]
        updates[key] = data.model[key]
        changes = true
    if not changes then return socket.sendJSON "error", {error: "No edits specified."}

    schema.Firestarter.findOne {_id: data.model._id}, (err, doc) ->
      return socket_error(socket, err) if err?
      schema.Response.find {firestarter_id: data.model._id}, (err, responses) ->
        return socket_error(socket, err) if err?
        unless utils.can_edit(session, doc)
          return socket.sendJSON("error", {error: "Permission denied"})
        unless utils.can_change_sharing(session, doc)
          delete updates.sharing
        for key, val of updates
          doc[key] = val
        doc.save (err, doc) ->
          return socket_error(socket, err) if err?
          async.parallel [
            (done) ->
              add_firestarter_event(doc, {
                type: "update"
                user: session.auth?.user_id
                anon_id: session.anon_id
                data: { action: updates }
              }, 0, done)
            (done) ->
              add_firestarter_search(doc, responses, done)
          ], (err) ->
            return socket_error(socket, err) if err?
            doc.sharing = utils.clean_sharing(session, doc)
            res = {model: doc.toJSON()}
            delete res.model.responses
            if data.callback? then socket.sendJSON data.callback, res
            sockrooms.broadcast("firestarter/" + doc.slug,
              "firestarter",
              res,
              socket.sid)


  #
  # Retrieve a firestarter with responses.
  #
  sockrooms.on 'firestarter/get_firestarter', (socket, session, data) ->
    unless data.slug?
      socket.sendJSON("error", {error: "Missing slug!"})
    schema.Firestarter.with_responses {slug: data.slug}, (err, model) ->
      if err?
        return socket_error(socket, err)
      else if not model?
        return socket_error(socket, "not found")
      else if not utils.can_view(session, model)
        return socket_error(socket, "Permission denied")
      else
        model.sharing = utils.clean_sharing(session, model)
        socket.sendJSON("firestarter", {
          model: model.toJSON()
        })
        add_firestarter_event(model, {
          type: "visit"
          user: session.auth?.user_id
          anon_id: session.anon_id
          data: {}
        }, 5000 * 60, (err) -> return socket_error(socket, err) if err?)
  
  sockrooms.on "firestarter/get_firestarter_list", (socket, session, data) ->
    if not data.callback?
      socket.sendJSON "error", {error: "Missing callback parameter."}
    else
      utils.list_accessible_documents(
        schema.Firestarter, session, (err, docs) ->
          return socket_error(socket, err) if err?
          socket.sendJSON data.callback, {docs: docs}
      )

  sockrooms.on "firestarter/get_firestarter_events", (socket, session, data) ->
    unless data.firestarter_id?
      return socket.sendJSON "error", {error: "Missing firestarter ID"}
    unless data.callback?
      return socket.sendJSON "error", {error: "Missing callback"}
    schema.Firestarter.findOne {_id: data.firestarter_id}, (err, doc) ->
      if not utils.can_view(session, doc)
        return socket.sendJSON "error", {error: "Permission denied"}
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
    async.waterfall [
      # Grab the firestarter and responses.
      (done) ->
        schema.Firestarter.findOne {_id: data.model.firestarter_id}, (err, firestarter) ->
          return done(err) if err?
          schema.Response.find {firestarter_id: data.model.firestarter_id}, (err, responses) ->
            return done(err) if err?
            unless utils.can_edit(session, firestarter)
              done("Permission denied")
            else
              done(null, firestarter, responses)

      # Save the response.
      (firestarter, responses, done) ->
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
            done(err, firestarter, responses, doc)
        else
          new schema.Response(updates).save (err, doc) ->
            done(err, firestarter, responses, doc)

      # Replace or insert the response, build search content
      (firestarter, responses, new_response, done) ->
        found = false
        for orig_response,i in responses
          if orig_response.id == new_response.id
            firestarter.responses.splice(i, 1, new_response._id)
            found = true
            break
        if not found
          firestarter.responses.push(new_response._id)

        # Get the search content.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in responses
        ).concat([new_response.response])).join("\n")

        # If this is a new response, save it to the firestarter's list.
        if not found
          firestarter.save (err, doc) ->
            done(err, doc, responses, new_response, search_content)
        else
          done(null, firestarter, responses, new_response, search_content)

    ], (err, firestarter, responses, new_response, search_content) ->
      # Call back to sockets.
      return socket_error(socket, err) if err?
      responseData = {model: new_response.toJSON()}
      sockrooms.broadcast("firestarter/" + firestarter.slug,
        "response",
        responseData,
        socket.sid)
      socket.sendJSON(data.callback, responseData) if data.callback?

      # Post search data
      add_firestarter_event(firestarter, {
        type: "append"
        user: new_response.user_id or null
        anon_id: session.anon_id
        via_user: session.auth?.user_id
        data: { action: new_response.toJSON() }
      }, 0)
      responses.push(new_response)
      add_firestarter_search(firestarter, responses)

  #
  # Delete a response
  #
  sockrooms.on "firestarter/delete_response", (socket, session, data) ->
    return done("No response._id specified") unless data.model._id?
    return done("No firestarter_id specified") unless data.model.firestarter_id?
    async.waterfall [
      (done) ->
        # Fetch firestarter and validate permissions.
        schema.Firestarter.findOne {_id: data.model.firestarter_id}, (err, firestarter) ->
          return done(err) if err?
          schema.Response.find {firestarter_id: data.model.firestarter_id}, (err, responses) ->
            return done(err) if err?
            return done("Firestarter not found.") unless firestarter?
            unless utils.can_edit(session, firestarter)
              return done("Permission denied")
          
            deleted_response = null
            # Get the deleted response.
            for response,i in responses
              if response._id.toString() == data.model._id
                deleted_response = responses.splice(i, 1)[0]
                break
            if deleted_response?
              # Remove the response ID from the firestarter model.
              for response_id,i in firestarter.responses
                if response_id.toString() == data.model._id
                  firestarter.responses.splice(i, 1)
                  break
              return done(null, firestarter, responses, deleted_response)
            else
              return done("Response not found")

      (firestarter, responses, deleted_response, done) ->
        # Build search content, save firestarter and response.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in responses
        )).join("\n")
        async.parallel [
          (done) -> firestarter.save(done)
          (done) -> deleted_response.remove(done)
        ], (err) ->
          done(err, firestarter, responses, deleted_response, search_content)

      (firestarter, responses, deleted_response, search_content, done) ->
        # Respond to the sockets
        responseData = {model: {_id: data.model._id}}
        socket.sendJSON(data.callback, responseData) if data.callback?
        sockrooms.broadcast("firestarter/" + firestarter.slug,
          "delete_response",
          responseData,
          socket.sid)

        add_firestarter_event(firestarter, {
          type: "trim"
          user: session.auth?.user_id
          anon_id: session.anon_id
          data: { action: deleted_response?.toJSON() }
        }, 0)
        add_firestarter_search(firestarter, responses)

    ], (err) ->
      return socket_error(socket, err) if err?

  return { app }

module.exports = { start }
