fs = require 'fs'
ETHERPAD_API_KEY = fs.readFileSync(__dirname + "/../vendor/etherpad-lite/APIKEY.txt", 'utf-8').trim()
SECRET = fs.readFileSync(__dirname + "/secrets/SECRET.txt", 'utf-8').trim()
API_KEY = fs.readFileSync(__dirname + "/secrets/APIKEY.txt", 'utf-8').trim()

base_url = "http://localhost:9000"
# Configuration:
module.exports = {
  # Make this unique, secret, and complex.  It's used for signing session cookies.
  "secret": SECRET
  # Mongodb host and port
  "dbhost": "localhost"
  "dbport": 27017,
  "dbname": "intertwinkles",
  # Make this unique, secret, and complex. It's used for authorizing API access
  # between InterTwinkles apps.
  "api_key": API_KEY
  # Path to a URL shortener that is configured to rewrite to {api_url}/r/.  If you don't have a short URL domain, use http://YOURDOMAIN/r/.
  "short_url_base": "#{base_url}/r/"
  # Domain to use for cookie suppressing alpha warning
  "ALPHA_COOKIE_DOMAIN": "localhost"

  # This is a list of client IP addresses that are allowed to access the API.
  # It should contain a list of IP's of the hosts for each InterTwinkles app.
  "api_clients": ["127.0.0.1"]
  # This contain a list of all API keys from authorized clients.
  "authorized_keys": [API_KEY]
  "api_url": base_url
  # Installed apps.
  "apps": {
    "www": {
      "name": "Home"
      "about": "Home page for InterTwinkles."
      "url": base_url
    },
    "firestarter": {
      "name": "Firestarter"
      "about": "Go arounds, ice breakers, intros. Get to know each other."
      "url": "#{base_url}/firestarter"
      "image": "#{base_url}/static/firestarter/img/firestarter_tile.png"
    },
    "resolve": {
      "name": "Resolve"
      "about": "Approve or reject a proposal with a group. Asynchronous voting and revising of proposals."
      "url": "#{base_url}/resolve"
      "image": "#{base_url}/static/resolve/img/resolve_tile.png"
    },
    "dotstorm": {
      "name": "Dotstorm"
      "about": "Structured brainstorming with sticky notes. Come up with new ideas."
      "url": "#{base_url}/dotstorm"
      "image": "#{base_url}/static/dotstorm/img/dotstorm_tile.png"
      "video": "https://www.youtube-nocookie.com/embed/dj_yW2WfsEw"
    },
    "twinklepad": {
      "name": "TwinklePad"
      "about": "Public or private collaborative document editing with etherpads"
      "url": "#{base_url}/twinklepad"
      "image": "#{base_url}/static/twinklepad/img/twinklepad_tile.png"
      "etherpad": {
        "url": "http://localhost:9001"
        "api_key": ETHERPAD_API_KEY
        "cookie_domain": "localhost"
        "backend_host": "localhost"
        "backend_port": 9001
      }
    },
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
