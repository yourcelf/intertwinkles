express       = require 'express'
socketio      = require 'socket.io'
RedisStore    = require('connect-redis')(express)
RoomManager   = require('iorooms').RoomManager
mongoose      = require 'mongoose'
logger        = require './logging'
schema        = require './schema'
_             = require 'underscore'
intertwinkles = require 'node-intertwinkles'

# See Cakefile for config definitions and defaults
start = (config) ->
  events = require('./events')(config)
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )

  app = express.createServer()
  sessionStore = new RedisStore

  #
  # Express Config
  #
  app.logger = logger # debug/dev logging
  app.configure ->
    app.use require('connect-assets')()
    #app.use express.logger()
    app.use express.bodyParser()
    app.use express.cookieParser()
    app.use express.session
      secret: config.secret
      key: 'express.sid'
      store: sessionStore

  app.configure 'development', ->
    app.use '/static', express.static(__dirname + '/../assets')
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets')

    app.use express.errorHandler({ dumpExceptions: true, showStack: true })
    app.get '/test', (req, res) ->
      res.render 'test'

  app.configure 'production', ->
    app.use '/static', express.static(__dirname + '/../assets', { maxAge: 1000*60*60*24 })
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets', { maxAge: 1000*60*60*24 })

  app.set 'view engine', 'jade'
  app.set 'view options', {layout: false}
  
  #
  # Sockets
  #
  io = socketio.listen(app, "log level": 0)
  iorooms = new RoomManager("/iorooms", io, sessionStore)
  require('./socket-connector').attach(config, iorooms)
  iorooms.authorizeJoinRoom = (session, name, callback) ->
    schema.Dotstorm.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")
  intertwinkles.attach(config, app, iorooms)
  

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



  app.get '/', (req, res) ->
    res.render 'dotstorm', context(req, {
      title: "DotStorm", slug: ""
    })

  # /d/:slug without trainling slash: redirect to slash.
  app.get /^\/d\/([^/]+)$/, (req, res) -> res.redirect "/d/#{req.params[0]}/"

  # /d/:slug/:action (action optional)
  app.get /\/d\/([^/]+)(\/.*)?/, (req, res) ->
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
            res.render 'dotstorm', context(req, {
              title: "DotStorm", slug: req.params[0]
            }, {
              dotstorm: doc
              ideas: (idea.serialize() for idea in ideas)
            })
            events.post_event(req.session, doc, "visit", {timeout: 60 * 1000 * 5})

  app.get '/i/:idea/json/', (req, res) ->
    schema.Idea.findOne {_id: req.params.idea}, (err, idea) ->
      return res.send("Server error", 500) if err?
      return res.send("Not found", 404) if not idea?
      schema.Dotstorm.findOne {_id: doc.dotstorm_id}, 'sharing', (err, dotstorm) ->
        return res.send("Server error", 500) if err?
        return res.send("Forbidden", 403) unless intertwinkles.can_view(req.session, dotstorm)
        return res.send("Not found", 404) if not dotstorm?
        res.send(idea: idea)

  # Embed read-only dostorm using embed slug.
  app.get '/e/:embed_slug', (req, res) ->
    constraint = embed_slug: req.params.embed_slug
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return res.send("Server errror", 500) if err?
      return res.send("Permission denied", 403) unless intertwinkles.can_view(req.session, doc)
      return res.send("Not found", 404) unless doc?
      res.render 'embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: null
        layout: false
      })

  # Embed group using group id.
  app.get '/g/:group_id', (req, res) ->
    constraint = "groups._id": req.params.group_id
    schema.Dotstorm.withLightIdeas constraint, (err, doc) ->
      return res.send("Server errror", 500) if err?
      return res.send("Permission denied", 403) unless intertwinkles.can_view(req.session, doc)
      return res.send("Not found", 404) unless doc?
      res.render 'embed', context(req, {
        title: doc.name or "DotStorm"
        dotstorm: doc
        group_id: req.params.group_id
        layout: false
      })

  # /g/:group_id : embed group

  require('./auth').route(app, config.host)

  app.listen config.port

  return { app, io, sessionStore, db }

module.exports = { start }
