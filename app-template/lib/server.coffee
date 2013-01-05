express       = require 'express'
socketio      = require 'socket.io'
intertwinkles = require 'node-intertwinkles'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
_             = require 'underscore'

start = (options) ->
  app = express.createServer()
  sessionStore = new RedisStore()
  io = socketio.listen(app, {"log level": 0})
  iorooms = new RoomManager("/iorooms", io, sessionStore)
  intertwinkles.attach(options, app, iorooms)

  #
  # Config
  #
  app.configure ->
    app.use require('connect-assets')()
    app.use express.bodyParser()
    app.use express.cookieParser()
    app.use express.session
      secret: options.secret
      key: 'express.sid'
      store: sessionStore

  app.configure 'development', ->
      app.use '/static', express.static(__dirname + '/../assets')
      app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets')
      app.use express.errorHandler {dumpExceptions: true, showStack: true}

  app.configure 'production', ->
    # Cache long time in production.
    app.use '/static', express.static(__dirname + '/../assets', { maxAge: 1000*60*60*24 })
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets', { maxAge: 1000*60*60*24 })

  app.set 'view engine', 'jade'

  #
  # Routes
  #
  
  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend({
        email: req?.session?.auth?.email or null
        groups: req?.session?.groups or null
      }, initial_data or {})
      conf: options.intertwinkles
    }, obj)


  # about

  app.get '/', (req, res) ->
    res.render 'index', context(req, {
      title: "InterTwinkles: Twinkling all over the InterWebs"
    })

  app.get '/about/', (req, res) ->
    res.render 'about/index', context(req, {
      title: "About InterTwinkles"
    })

  app.get '/about/terms/', (req, res) ->
    res.render 'about/terms', context(req, {
      title: "Terms of Use"
    })

  app.get '/about/privacy/', (req, res) ->
    res.render 'about/privacy', context(req, {
      title: "Privacy Policy"
    })

  app.get '/about/related/', (req, res) ->
    res.render 'about/related', context(req, {
      title: "Related Work"
    })

  # edit groups / settings

  app.get '/profiles/settings/', (req, res) ->
    res.render 'profiles/settings', context({
      title: "Profile settings"
    }, req)
  app.post '/profile/settings/', (req, res) ->

  app.listen (options.port)

module.exports = {start}
