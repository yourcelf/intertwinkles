express       = require 'express'
RoomManager   = require('iorooms').RoomManager
schema        = require './schema'
_             = require 'underscore'
intertwinkles = require '../../../lib/intertwinkles'

# See Cakefile for config definitions and defaults
start = (config, app, io, sessionStore) ->
  events = require('./events')(config)

  iorooms = new RoomManager("/io-dotstorm", io, sessionStore)
  require('./socket-connector').attach(config, iorooms)
  iorooms.authorizeJoinRoom = (session, name, callback) ->
    schema.Dotstorm.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")

  #
  # Routes
  # 

  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "dotstorm"},
        intertwinkles.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: intertwinkles.clean_conf(config)
      flash: req.flash()
    }, obj)

  app.get /\/dotstorm$/, (req, res) -> res.redirect "/dotstorm/"
  app.get '/dotstorm/', (req, res) ->
    res.render 'dotstorm/dotstorm', context(req, {
      title: "DotStorm", slug: ""
    })

  # /d/:slug without trainling slash: redirect to slash.
  app.get /^\/dotstorm\/d\/([^/]+)$/, (req, res) -> res.redirect "/dotstorm/d/#{req.params[0]}/"

  # /d/:slug/:action (action optional)
  app.get /\/dotstorm\/d\/([^/]+)(\/.*)?/, (req, res) ->
    error_check = (err, doc) ->
      return res.send("Server errror", 500) if err?
      return res.send("Not found", 404) unless doc?
      return res.send("Permission denied", 403) unless intertwinkles.can_view(req.session, doc)
      return true

    if req.params[1] == "/json/"
      schema.Dotstorm.withLightIdeas {slug: req.params[0]}, (err, doc) ->
        if error_check(err, doc) == true
          doc.sharing = intertwinkles.clean_sharing(req.session, doc)
          res.send(dotstorm: doc)
    else
      schema.Dotstorm.findOne {slug: req.params[0]}, (err, doc) ->
        if error_check(err, doc) == true
          ideas = schema.Idea.findLight {dotstorm_id: doc._id}, (err, ideas) ->
            return res.send("Server error", 500) if err?
            res.render 'dotstorm/dotstorm', context(req, {
              title: "DotStorm", slug: req.params[0]
            }, {
              dotstorm: doc
              ideas: (idea.serialize() for idea in ideas)
            })
            events.post_event(req.session, doc, "visit", {timeout: 60 * 1000 * 5})

  app.get '/dotstorm/i/:idea/json/', (req, res) ->
    schema.Idea.findOne {_id: req.params.idea}, (err, idea) ->
      return res.send("Server error", 500) if err?
      return res.send("Not found", 404) if not idea?
      schema.Dotstorm.findOne {_id: doc.dotstorm_id}, 'sharing', (err, dotstorm) ->
        return res.send("Server error", 500) if err?
        return res.send("Forbidden", 403) unless intertwinkles.can_view(req.session, dotstorm)
        return res.send("Not found", 404) if not dotstorm?
        res.send(idea: idea)

  # Embed read-only dostorm using embed slug.
  app.get '/dotstorm/e/:embed_slug', (req, res) ->
    constraint = embed_slug: req.params.embed_slug
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return res.send("Server errror", 500) if err?
      return res.send("Permission denied", 403) unless intertwinkles.can_view(req.session, doc)
      return res.send("Not found", 404) unless doc?
      res.render 'dotstorm/embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: null
        layout: false
      })

  # Embed group using group id.
  app.get '/dotstorm/g/:group_id', (req, res) ->
    constraint = "groups._id": req.params.group_id
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return res.send("Server errror", 500) if err?
      return res.send("Permission denied", 403) unless intertwinkles.can_view(req.session, doc)
      return res.send("Not found", 404) unless doc?
      res.render 'dotstorm/embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: req.params.group_id
        layout: false
      })

module.exports = { start }
