express       = require 'express'
_             = require 'underscore'
utils         = require '../../../lib/utils'
logger        = require('log4js').getLogger()

# See Cakefile for config definitions and defaults
start = (config, app, sockrooms) ->
  events = require('./events')(config)
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  dslib = require("./dslib")(config)

  sockrooms.addChannelAuth "dotstorm", (session, room, callback) ->
    name = room.split("/")[1]
    schema.Dotstorm.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      if utils.can_view(session, doc)
        callback(null, true)
      else
        callback(null, false)

  #
  # Routes
  # 

  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "dotstorm"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash()
    }, obj)

  utils.append_slash(app, "/dotstorm")
  app.get '/dotstorm/', (req, res) ->
    res.render 'dotstorm/dotstorm', context(req, {
      title: "DotStorm", slug: ""
    })

  utils.append_slash(app, "/dotstorm/new")
  app.get '/dotstorm/new/', (req, res) ->
    res.render 'dotstorm/dotstorm', context(req, {
      title: "New DotStorm", slug: ""
    })

  # /d/:slug/:action (action optional)
  utils.append_slash(app, "/dotstorm/d/([^/]+)(/[^/]+)?")
  app.get "/dotstorm/d/:slug/:action?/:id?/", (req, res) ->
    passes_checks = (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        return www_methods.permission_denied(req, res)
      return true

    if req.params.action == "json"
      schema.Dotstorm.findOne({slug: req.params.slug}).populate(
        'groups.ideas'
      ).exec (err, doc) ->
        return unless passes_checks(err, doc)
        res.setHeader("Content-Type", "application/json; charset=utf-8")
        res.setHeader("Content-Disposition",
          "attachment; filename=\"#{encodeURIComponent(req.params.slug)}.json\"")
        return res.send(doc.exportJSON())
    else if req.params.action == "csv"
      rows = []
      schema.Dotstorm.findOne({slug: req.params.slug}).populate(
        'groups.ideas'
      ).exec (err, doc) ->
        return unless passes_checks(err, doc)
        res.setHeader("Content-Type", "text/csv; charset=utf-8")
        res.setHeader("Content-Disposition",
          "attachment; filename=\"#{encodeURIComponent(req.params.slug)}.csv\"")
        return res.send(utils.array_to_csv(doc.exportRows()))
    else
      schema.Dotstorm.findOne {slug: req.params.slug}, (err, doc) ->
        return unless passes_checks(err, doc)
        ideas = schema.Idea.findLight {dotstorm_id: doc._id}, (err, ideas) ->
          return www_methods.handle_error(req, res, err) if err?
          res.render 'dotstorm/dotstorm', context(req, {
            title: "DotStorm", slug: req.params.slug
          }, {
            dotstorm: doc
            ideas: (idea.serialize() for idea in ideas)
          })
          events.post_event(req.session, doc, "visit")
          return

  utils.append_slash(app, "/dotstorm/i/[^/]+/json")
  app.get '/dotstorm/i/:idea/json/', (req, res) ->
    schema.Idea.findOne {_id: req.params.idea}, (err, idea) ->
      return res.status(500).send("Server error") if err?
      return res.status(404).send("Not found") if not idea?
      schema.Dotstorm.findOne {_id: doc.dotstorm_id}, 'sharing', (err, dotstorm) ->
        return www_methods.handle_error(req, res, err) if err?
        return www_methods.not_found(req, res) unless dotstorm?
        unless utils.can_view(req.session, dotstorm)
          return www_methods.permission_denied(req, res)
        res.send(idea: idea)

  # Embed read-only dostorm using embed slug.
  utils.append_slash(app, "/dotstorm/e/[^/]+")
  app.get '/dotstorm/e/:embed_slug/', (req, res) ->
    constraint = embed_slug: req.params.embed_slug
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        return www_methods.permission_denied(req, res)
      res.render 'dotstorm/embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: null
        layout: false
      })

  # Embed group using group id.
  utils.append_slash(app, "/dotstorm/g/[^/]+")
  app.get '/dotstorm/g/:group_id/', (req, res) ->
    constraint = "groups._id": req.params.group_id
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        return www_methods.permission_denied(req, res)
      res.render 'dotstorm/embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: req.params.group_id
        layout: false
      })

  sockrooms.on "dotstorm/check_slug", (socket, session, data) ->
    return sockrooms.handleError(socket, "Missing slug") unless data.slug?
    schema.Dotstorm.findOne {slug: data.slug}, '_id', (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON(data.callback or "dotstorm:check_slug", {available: not doc?})

  broadcast_dotstorm = (err, socket, session, doc, address) ->
    return sockrooms.handleError(socket, err) if err?
    orig_sharing = doc.sharing
    # Must broadcast back to socket directly, in case we're creating, and thus
    # haven't joined yet.
    doc.sharing = utils.clean_sharing(session, doc)
    socket.sendJSON address or "dotstorm:dotstorm", {dotstorm: doc}

    # Sanitize sharing for broadcast individually.
    sockrooms.roomSocketSessionMap "dotstorm/#{doc.id}", (err, socket, sess) ->
      return logger.error(err) if err?
      if sess.session_id != session.session_id
        doc.sharing = utils.clean_sharing(sess, {sharing: orig_sharing})
        socket.sendJSON "dotstorm:dotstorm", {dotstorm: doc}
 
  broadcast_idea = (err, socket, session, doc) ->
    return sockrooms.handleError(socket, err) if err?
    idea_json = doc.serialize()
    delete idea_json.drawing
    sockrooms.broadcast(
      "dotstorm/" + doc.dotstorm_id,
      "dotstorm:ideas",
      {ideas: [idea_json]},
    )

  sockrooms.on 'dotstorm/create_dotstorm', (socket, session, data) ->
    dslib.create_dotstorm session, data, (err, dotstorm) ->
      broadcast_dotstorm(err, socket, session, dotstorm, data.callback)

  sockrooms.on 'dotstorm/edit_dotstorm', (socket, session, data) ->
    dslib.edit_dotstorm session, data, (err, dotstorm) ->
      broadcast_dotstorm(err, socket, session, dotstorm)

  sockrooms.on 'dotstorm/edit_group_label', (socket, session, data) ->
    dslib.edit_group_label session, data, (err, dotstorm) ->
      broadcast_dotstorm(err, socket, session, dotstorm)

  sockrooms.on 'dotstorm/rearrange', (socket, session, data) ->
    dslib.rearrange session, data, (err, dotstorm) ->
      broadcast_dotstorm(err, socket, session, dotstorm)

  sockrooms.on 'dotstorm/get_idea', (socket, session, data) ->
    dslib.get_idea session, data, (err, dotstorm, idea) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON(data.callback or "dotstorm:ideas", {ideas: [idea]})

  sockrooms.on 'dotstorm/get_dotstorm', (socket, session, data) ->
    dslib.get_dotstorm session, data, (err, dotstorm, light_ideas) ->
      return sockrooms.handleError(socket, err) if err?
      dotstorm.sharing = utils.clean_sharing(session, dotstorm)
      socket.sendJSON("dotstorm:ideas", {ideas: light_ideas})
      socket.sendJSON("dotstorm:dotstorm", {dotstorm: dotstorm})

  sockrooms.on 'dotstorm/create_idea', (socket, session, data) ->
    dslib.create_idea session, data, (err, dotstorm, idea) ->
      broadcast_idea(err, socket, session, idea)
      broadcast_dotstorm(err, socket, session, dotstorm)

  sockrooms.on 'dotstorm/edit_idea', (socket, session, data) ->
    dslib.edit_idea session, data, (err, dotstorm, idea) ->
      broadcast_idea(err, socket, session, idea)

module.exports = { start }
