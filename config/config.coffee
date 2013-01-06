# Configuration:
module.exports = {
  # Make this unique, secret, and complex.  It's used for signing session cookies.
  "secret": "aC]l'0IWX;vi>:IptJ=+XP?s75wQDe1W|apN6.Pw|Z?5zfuTZ%Th}E*Ny03_)RW~"
  # Mongodb host and port
  "dbhost": "localhost"
  "dbport": 27017,
  "dbname": "intertwinkles",
  # Host and port where an app is listening (overridden by each app).
  "host": "localhost"
  "port": 9000
  # Make this unique, secret, and complex. It's used for authorizing API access
  # between InterTwinkles apps.
  "api_key": "1kjJiF6aK4GLcVqDomIpbsy6mJwZlEjF2mCya6mJLYgNo1BTkAem6mxbuivBpq8J"
  # The formatted name of the app.
  "name": "Example"
  # A short sentence describing the app for menus.
  "about": "This is an example description."
  # A 64x64 image for the app (optional).
  "image": undefined
  # An optional youtube video link for the app.
  "video": undefined
  # Path to a URL shortener that is configured to rewrite to {api_url}/r/.  If you don't have a short URL domain, use http://YOURDOMAIN/r/.
  "short_url_base": "http://localhost:9000/r/"
  # Domain to use for cookie suppressing alpha warning
  "ALPHA_COOKIE_DOMAIN": "localhost"

  # This is a list of client IP addresses that are allowed to access the API.
  # It should contain a list of IP's of the hosts for each InterTwinkles app.
  "api_clients": ["127.0.0.1"]
  # This contain a list of all API keys from authorized clients.
  "authorized_keys": ["1kjJiF6aK4GLcVqDomIpbsy6mJwZlEjF2mCya6mJLYgNo1BTkAem6mxbuivBpq8J"]
  "api_url": "http://localhost:9000"
  # Installed apps.
  "apps": {
    "www": {
      "name": "Home"
      "about": "Home page for InterTwinkles."
      "url": "http://localhost:9000"
      "url_prefix": ""
    },
    "firestarter": {
      "name": "Firestarter"
      "about": "Go arounds, ice breakers, intros. Get to know each other."
      "url_prefix": "/firestarter"
      "image": "/static/firestarter/img/firestarter_tile.png"
    }
  }
}

#config = {}
#
## To remove an app, comment it out.
#config.apps = {
#  "home": {
#    "url": urls.home
#    #"url": "http://dev.intertwinkles.org"
#    "name": "Home"
#    "about": "Home page for InterTwinkles."
#    "dbname": "intertwinkles",
#    "port": 9000
#    # The API runs out of "home", so it needs to control access.  This is a
#    # list of client IP addresses that are allowed to access the API.  It
#    # should contain a list of IP's of the hosts for each InterTwinkles app.
#    "api_clients": ["127.0.0.1"]
#    # This should contain a list of all API keys from all apps.
#    "authorized_keys": ["1kjJiF6aK4GLcVqDomIpbsy6mJwZlEjF2mCya6mJLYgNo1BTkAem6mxbuivBpq8J"]
#  }
#
#  "resolve": {
#    "url": urls.resolve
#    "dbname": "resolve"
#    "port": 9001
#    "name": "Resolve"
#    "about": "Approve or reject a proposal with a group. Asynchronous voting and revising of proposals."
#    "image": "/static/img/resolve_tile.png"
#  }
#
#  "firestarter": {
#    "url": urls.firestarter
#    "dbname": "firestarter"
#    "port": 9002
#    "name": "Firestarter"
#    "about": "Go arounds, ice breakers, intros. Get to know each other."
#    "image": "/static/img/firestarter_tile.png"
#  }
#
#  "dotstorm": {
#    "url": urls.dotstorm
#    #"url": "http://dotstorm.dev.intertwinkles.org"
#    "dbname": "twinkledotstorm"
#    "port": 9003
#    "name": "Dotstorm"
#    "about": "Structured brainstorming with sticky notes. Come up with new ideas."
#    "image": "/static/img/dotstorm_tile.png"
#    "video": "https://www.youtube-nocookie.com/embed/dj_yW2WfsEw"
#  }
#
#  "twinklepad": {
#    "url": urls.twinklepad
#    #"url": "http://twinklepad.dev.intertwinkles.org"
#    "dbname": "twinklepad"
#    "port": 9004
#    # The backend
#    "etherpad": {
#      "api_key": "PuHTWuOXv7m0UziZMBGfxyJwotYEO6Qy"
#      #"url": "http://localhost:9005"
#      "url": urls.etherpad
#      "host": "localhost"
#      "port": 9005
#    }
#    "name": "TwinklePad",
#    "about": "Collaborative document editing with etherpads"
#    # Path relative to this app's url.
#    "image": "/static/img/twinklepad_tile.png"
#  }
#}
#
#config.proxy = {
#  # The port on which the proxy server will listen.  This should be a public
#  # port such as 80, or be proxied to from another reverse proxy such as
#  # HAProxy, Varnish, or nginx.
#  port: 8080
#  # The routes are built from the app config programmatically below.
#  routes: []
#}
#
#app_list = {}
#for label, app of config.apps
#  # Put the base app underneath.
#  app = _.extend {}, base_app_config, app
# 
#  app_list[label] = {}
#  # Add the list of all apps to each app.
#  for prop in ["url", "name", "about", "image", "video"]
#    app_list[label][prop] = app[prop]
#  app.apps = app_list
#  app.api_url = config.apps.home.url
#
#  config.apps[label] = app
#  
#  # Add each app to the proxies list.
#  config.proxy.routes.push({
#    url: app.url
#    port: app.port
#    host: app.host
#  })
#
## Add the etherpad to the proxies list.
#if config.apps.twinklepad.etherpad?
#  config.proxy.routes.push {
#    url: config.apps.twinklepad.etherpad.url
#    host: config.apps.twinklepad.etherpad.host
#    port: config.apps.twinklepad.etherpad.port
#  }
#
#module.exports = config
