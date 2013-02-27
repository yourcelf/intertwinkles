express        = require 'express'
RedisStore     = require('connect-redis')(express)
mongoose       = require 'mongoose'
sockjs         = require 'sockjs'
_              = require 'underscore'
connect_assets = require 'connect-assets'
stylus         = require 'stylus'
log4js         = require 'log4js'

utils          = require './utils'
RoomManager    = require("./socket_server").RoomManager
socket_routes  = require './socket_routes'
www_routes     = require "./www_routes"
api_routes     = require "./api_routes"
# Include code lines in stack traces.
require "better-stack-traces"

# Allow express to look for views in app subfolders, and not just the one
# top-level view folder.  Monkey patch the express view lookup to consider
# multiple folders. http://stackoverflow.com/a/11326059/85461
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
  # Logger: log4js
  log4js.configure(__dirname + '/../config/logging.json')
  logger = log4js.getLogger()

  # App: express
  app = express.createServer()
  sessionStore = new RedisStore()

  # Socket connections: sockjs
  sockserver = sockjs.createServer({
    log: (severity, message) -> logger[severity](message)
  })
  sockserver.installHandlers(app, {prefix: "/sockjs"})
  sockrooms = new RoomManager(sockserver, sessionStore)
  socket_routes.route(config, sockrooms)

  # Database mongodb
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )

  # Paths to view, asset, and static folders.
  view_folders = [__dirname + "/../views"]
  asset_pipeline_folders = [__dirname + "/../assets"]
  static_folders = [__dirname + "/../assets"]
  for key, appconf of config.apps
    continue if key == "www"
    view_folders.push("#{__dirname}/../plugins/#{key}/views")
    asset_pipeline_folders.push("#{__dirname}/../plugins/#{key}/assets")
    static_folders.push("#{__dirname}/../plugins/#{key}/assets")

  ###
  # Configure express
  ###

  app.use express.bodyParser({keepExtensions: true})
  app.use express.cookieParser()
  app.use express.session({
    secret: config.secret
    key: 'express.sid'
    store: sessionStore
    cookie: {
      path: '/'
      httpOnly: false # we need to access the session from the socket client
      maxAge: 1000*60*60*24*7 # one week?
    }
  })
  # Might want this later...
  #app.use log4js.connectLogger(logger, {level: log4js.levels.INFO})
  app.set 'view engine', 'jade'
  app.set 'view options', {layout: false}
  app.set "views", view_folders

  ###
  # static files
  ###
  
  app.use connect_assets(src: asset_pipeline_folders)
  # Don't prefix connect-assets' css and js paths by default.
  css.root = ''
  js.root = ''

  app.configure 'development', ->
    logger.setLevel(log4js.levels.DEBUG)
    app.use "/uploads/", express.static(__dirname + '/../uploads')
    for folder in static_folders
      app.use "/static/", express.static(folder)

  app.configure 'production', ->
    logger.setLevel(log4js.levels.ERROR)
    timeout = {maxAge: 1000*60*60*24}
    app.use "/uploads/", express.static(__dirname + '/../uploads', timeout)
    for folder in static_folders
      app.use "/static/", express.static(folder, timeout)

  ###
  # Express routes
  ###

  # Base routes for home page, auth, groups, profiles, search
  www_routes.route(config, app, sockrooms)
  api_routes.route(config, app)
  # Routes for plugins.
  for key, appconf of config.apps
    continue if key == "www"
    require("../plugins/#{key}/lib/server").start(config, app, sockrooms)

  # 404 route -- must be last, after all other routes, as it defines a
  # wildcard.
  www_routes.route_errors(config, app)

  ###
  # Run
  ###

  app.listen config.port

  return {app, logger, db }


module.exports = {start}
