#require("nodetime").profile() # debug analytics
express        = require 'express'
connect        = require 'connect'
http           = require 'http'
RedisStore     = require('connect-redis')(express)
flash          = require 'connect-flash'
mongoose       = require 'mongoose'
sockjs         = require 'sockjs'
_              = require 'underscore'
log4js         = require 'log4js'

utils          = require './utils'
RoomManager    = require("./socket_server").RoomManager
socket_routes  = require './www_socket_routes'
www_routes     = require "./www_routes"
api_routes     = require "./api_routes"
yaac           = require "yaac"

# Include code lines in stack traces.
require "better-stack-traces"

# Allow express to look for views in app subfolders, and not just the one
# top-level view folder.  Monkey patch the express view lookup to consider
# multiple folders. http://stackoverflow.com/a/11326059/85461
enable_multiple_view_folders = () ->
  View = require("../node_modules/express/lib/view")
  lookup_proxy = View.prototype.lookup
  View.prototype.lookup = (viewName) ->
    if this.root instanceof Array
      for root in this.root
        context = {root: root}
        match = lookup_proxy.call(context, viewName)
        return match if match?
      return null
    return lookup_proxy.call(this, viewName)
enable_multiple_view_folders()

start = (config) ->
  # Logger: log4js
  log4js.configure(__dirname + '/../config/logging.json')
  logger = log4js.getLogger("www")

  # App: express
  app = express()
  server = http.createServer(app)
  sessionStore = new RedisStore()

  # Socket connections: sockjs
  sockserver = sockjs.createServer({
    log: (severity, message) -> logger[severity](message)
  })
  sockserver.installHandlers(server, {prefix: "/sockjs"})
  sockrooms = new RoomManager(sockserver, sessionStore, config.secret)
  socket_routes.route(config, sockrooms)

  # Database mongodb
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )

  ###
  # Configure express
  ###

  app.use log4js.connectLogger(logger, {level: log4js.levels.INFO})
  app.configure 'development', -> logger.setLevel(log4js.levels.DEBUG)
  app.configure 'production',  -> logger.setLevel(log4js.levels.ERROR)
  app.enable "trust proxy"
  app.use connect.compress()
  app.use express.bodyParser({keepExtensions: true})
  app.use express.cookieParser()
  app.use express.session({
    secret: config.secret
    key: 'express.sid'
    store: sessionStore
    cookie: {
      path: '/'
      httpOnly: false # we need to access the session from the socket client
      maxAge: 1000*60*60*24*7 # one week
    }
  })
  app.use flash()
  
  # Templates
  app.set 'view engine', 'jade'
  view_folders = [__dirname + "/../views"]
  asset_folders = [__dirname + "/../assets"]
  for key, appconf of config.apps
    continue if key == "www"
    view_folders.push("#{__dirname}/../plugins/#{key}/views")
    asset_folders.push("#{__dirname}/../plugins/#{key}/assets")
  app.set "views", view_folders

  ###
  # static files
  ###
  expiry = {maxAge: 1000 * 60 * 60 * 24}
  app.use "/uploads/", express.static(__dirname + "/../uploads", expiry)
  app.use "/static/", express.static(__dirname + "/../builtAssets", expiry)
  app.locals.asset = yaac({
    searchPath: asset_folders
    dest: __dirname + "/../builtAssets"
  }).asset


  ###
  # Express routes
  ###

  app.use(app.router)

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

  server.listen(config.port)

  return {app, server, logger, sockrooms, sockserver, db }


module.exports = {start}
