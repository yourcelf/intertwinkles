express        = require 'express'
socketio       = require 'socket.io'
RedisStore     = require('connect-redis')(express)
mongoose       = require 'mongoose'
_              = require 'underscore'
connect_assets = require 'connect-assets'
stylus         = require 'stylus'
log4js         = require 'log4js'

intertwinkles  = require './intertwinkles'
socket_routes  = require './socket_routes'

# Logger

# Allow express to look for views in app subfolders, and not just the one
# top-level view folder.
# See http://stackoverflow.com/questions/11315351/multiple-view-paths-on-node-js-express/11326059#11326059
enable_multiple_view_folders = (express) ->
  lookup_proxy = express.view.lookup
  express.view.lookup = (view, options) ->
    if options.root instanceof Array
      opts = _.extend {}, options
      for root in options.root
        opts.root = root
        match = lookup_proxy.call(this, view, opts)
        if match.exists
          return match
      return null
    return lookup_proxy.call(express.view, view, options)
enable_multiple_view_folders(express)

start = (config) ->
  log4js.configure(__dirname + '/../config/logging.json')
  logger = log4js.getLogger()
  app = express.createServer()
  sessionStore = new RedisStore()
  io = socketio.listen(app, {"log level": 0})
  socket_routes.route(config, io, sessionStore)
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )

  app.use express.bodyParser({keepExtensions: true})
  app.use express.cookieParser()
  app.use express.session
    secret: config.secret
    key: 'express.sid'
    store: sessionStore
  app.set 'view engine', 'jade'
  app.set 'view options', {layout: false}
  app.use log4js.connectLogger(logger, {level: log4js.levels.INFO})

  # static files
  app.configure 'development', ->
    logger.setLevel(log4js.levels.DEBUG)
    app.use "/static/", express.static(__dirname + '/../assets')
    app.use "/uploads/", express.static(__dirname + '/../uploads')

  app.configure 'production', ->
    logger.setLevel(log4js.levels.ERROR)
    app.use "/static/", express.static(__dirname + '/../assets',
      {maxAge: 1000*60*60*24})
    app.use "/uploads/", express.static(__dirname + '/../uploads',
      {maxAge: 1000*60*60*24})

  view_folders = [__dirname + "/../views"]
  asset_folders = [__dirname + "/../assets"]

  # API routes
  require("./api_routes").route(config, app)
  # Base routes for home page, auth, groups, profiles, search
  require("./www_routes").route(config, app, io, sessionStore)

  for key, appconf of config.apps
    continue if key == "www"
    # App-specific routes
    require("../plugins/#{key}/lib/server").start(config, app, io, sessionStore)

    app.configure 'development', ->
      app.use "/static/", express.static("#{__dirname}/../plugins/#{key}/assets")

    app.configure 'production', ->
      app.use "/static/", express.static("#{__dirname}/../plugins/#{key}/assets", {
        maxAge: 1000*60*60*24
      })
    view_folders.push("#{__dirname}/../plugins/#{key}/views")
    asset_folders.push("#{__dirname}/../plugins/#{key}/assets")

  app.use connect_assets(src: asset_folders)
  # Don't prefix connect-assets' css and js paths by default.
  css.root = ''
  js.root = ''

  app.set "views", view_folders

  app.listen config.port
  return {app, db, logger}

module.exports = {start}
