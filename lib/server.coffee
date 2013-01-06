express        = require 'express'
socketio       = require 'socket.io'
intertwinkles  = require 'node-intertwinkles'
RedisStore     = require('connect-redis')(express)
RoomManager    = require('iorooms').RoomManager
mongoose       = require 'mongoose'
_              = require 'underscore'
connect_assets = require 'connect-assets'

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
  app = express.createServer()
  sessionStore = new RedisStore()
  io = socketio.listen(app, {"log level": 0})
  iorooms = new RoomManager("/io-intertwinkles", io, sessionStore)
  intertwinkles.attach(config, app, iorooms)
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

  # node-intertwinkles static files
  app.configure 'development', ->
    app.use "/static/", express.static(
      __dirname + '/../node_modules/node-intertwinkles/assets')
  app.configure 'production', ->
    app.use "/static/", express.static(
      __dirname + '/../node_modules/node-intertwinkles/assets',
      {maxAge: 1000*60*60*24})

  view_folders = [__dirname + "/../views"]
  asset_folders = [__dirname + "/../node_modules/node-intertwinkles/assets"]
  for key, appconf of config.apps
    # App-specific routes
    require("./#{key}/lib/server").start(config, app, sessionStore, io)

    app.configure 'development', ->
      app.use "/static/", express.static("#{__dirname}/#{key}/assets")

    app.configure 'production', ->
      app.use "/static/", express.static("#{__dirname}/#{key}/assets", {
        maxAge: 1000*60*60*24
      })
    view_folders.push("#{__dirname}/#{key}/views")
    asset_folders.push("#{__dirname}/#{key}/assets")

  app.use connect_assets(src: asset_folders)
  # Don't prefix connect-assets' css and js paths by default.
  css.root = ''
  js.root = ''

  app.set "views", view_folders

  app.listen 9000
  return {app}

module.exports = {start}
