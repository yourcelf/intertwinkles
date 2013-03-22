express       = require 'express'
_             = require 'underscore'
utils         = require '../../../lib/utils'

# See Cakefile for config definitions and defaults
start = (config, app, sockrooms) ->
  events = require('./events')(config)
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)

  sockrooms.addChannelAuth "dotstorm", (session, room, callback) ->
    name = room.split("/")[1]
    schema.Dotstorm.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if utils.can_view(session, doc)
        callback(null, true)
      else
        callback(null, false)

  require('./socket-connector').attach(config, sockrooms)

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

  # /d/:slug/:action (action optional)
  utils.append_slash(app, "/dotstorm/d/([^/]+)(/[^/]+)?")
  app.get "/dotstorm/d/:slug/:action?/", (req, res) ->
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
        return res.send(doc.exportJSON())
    else if req.params.action == "csv"
      rows = []
      schema.Dotstorm.findOne({slug: req.params.slug}).populate(
        'groups.ideas'
      ).exec (err, doc) ->
        return unless passes_checks(err, doc)
        res.setHeader("Content-Type", "text/csv; charset=utf-8")
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
          events.post_event(req.session, doc, "visit", {timeout: 60 * 1000 * 5})
          return

  utils.append_slash(app, "/dotstorm/i/[^/]+/json")
  app.get '/dotstorm/i/:idea/json/', (req, res) ->
    schema.Idea.findOne {_id: req.params.idea}, (err, idea) ->
      return res.status(500).send("Server error") if err?
      return res.status(404).send("Not found") if not idea?
      schema.Dotstorm.findOne {_id: doc.dotstorm_id}, 'sharing', (err, dotstorm) ->
        return res.status(500).send("Server error") if err?
        unless utils.can_view(req.session, dotstorm)
          return res.status(403).send("Forbidden")
        return res.status(404).send("Not found") if not dotstorm?
        res.send(idea: idea)

  # Embed read-only dostorm using embed slug.
  utils.append_slash(app, "/dotstorm/e/[^/]+")
  app.get '/dotstorm/e/:embed_slug/', (req, res) ->
    constraint = embed_slug: req.params.embed_slug
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      unless utils.can_view(req.session, doc)
        return www_methods.permission_denied(req, res)
      return www_methods.not_found(req, res) unless doc?
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
      unless utils.can_view(req.session, doc)
        return www_methods.permission_denied(req, res)
      return www_methods.not_found(req, res) unless doc?
      res.render 'dotstorm/embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: req.params.group_id
        layout: false
      })

module.exports = { start }
