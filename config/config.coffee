#
# Configuration for InterTwinkles.  Set domains and ports in `domains.coffee`;
# all other settings below.
#

fs = require 'fs'
SECRET = fs.readFileSync(__dirname + "/secrets/SECRET.txt", 'utf-8').trim()
API_KEY = fs.readFileSync(__dirname + "/secrets/API_KEY.txt", 'utf-8').trim()
ETHERPAD_API_KEY = fs.readFileSync(
  __dirname + "/../vendor/etherpad-lite/APIKEY.txt", 'utf-8').trim()
domains = require './domains'
base_url = domains.front_end_url

config = {
  # The port on which intertwinkles listens.
  port: domains.base_port
  # Make this unique, secret, and complex.  It's used for signing session cookies.
  secret: SECRET
  # Mongodb host and port
  dbhost: "localhost"
  dbport: 27017,
  dbname: "intertwinkles"
  # The API key this app uses to make intertwinkles requests.
  api_key: API_KEY
  # Path to a URL shortener that is configured to rewrite to {api_url}/r/.  If
  # you don't have a short URL domain configured, use {api_url}/r/.
  short_url_base: domains.short_url_base
  # Domain to use for cookie suppressing alpha warning
  alpha_cookie_domain: domains.alpha_cookie_domain
  # This is a list of client IP addresses that are allowed to access the API.
  # It should contain a list of IP's of the hosts for each InterTwinkles app.
  api_clients: ["127.0.0.1"]
  # The list of API keys we will accept for connecting clients.  Should include
  # at least our own key.
  authorized_keys: [API_KEY]
  api_url: base_url
  # Installed apps.
  apps: {
    www: {
      name: "Home"
      about: "Home page for InterTwinkles."
      url: base_url
    }
    firestarter: {
      name: "Firestarter"
      about: "Go arounds, ice breakers, intros. Get to know each other."
      url: "#{base_url}/firestarter"
      image: "#{base_url}/static/firestarter/img/firestarter_tile.png"
    }
    resolve: {
      name: "Resolve"
      about: "Approve or reject a proposal with a group. Asynchronous voting and revising of proposals."
      url: "#{base_url}/resolve"
      image: "#{base_url}/static/resolve/img/resolve_tile.png"
    }
    dotstorm: {
      name: "Dotstorm"
      about: "Structured brainstorming with sticky notes. Come up with new ideas."
      url: "#{base_url}/dotstorm"
      image: "#{base_url}/static/dotstorm/img/dotstorm_tile.png"
      video: "https://www.youtube-nocookie.com/embed/dj_yW2WfsEw"
    }
    twinklepad: {
      name: "TwinklePad"
      about: "Public or private collaborative document editing with etherpads"
      url: "#{base_url}/twinklepad"
      image: "#{base_url}/static/twinklepad/img/twinklepad_tile.png"
      etherpad: {
        url: domains.etherpad_url
        api_key: ETHERPAD_API_KEY
        cookie_domain: domains.etherpad_cookie_domain
      }
    }
  }
}
module.exports = config
