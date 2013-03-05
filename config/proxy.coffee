#
# Configuration of proxy server, for resolving public-facing URLs to the
# backend host and etherpad instances.
#
# Launch the proxy server with `cake runproxy`.
#

domains           = require './domains'
etherpad_settings = require './etherpad/_read_etherpad_settings'

module.exports = {
  listen: domains.proxy_port
  routes: [{
    url: domains.front_end_url
    host: "localhost"
    port: domains.base_port
  }, {
    url: domains.etherpad_url
    host: "localhost"
    port: etherpad_settings.port
  },
  # Redirect hosts
  { url: "http://dev.intertwinkles.org", host: "localhost", port: domains.redirect_port },
  { url: "http://www.intertwinkles.org", host: "localhost", port: domains.redirect_port },
  { url: "http://www.intertwinkles.com", host: "localhost", port: domains.redirect_port },
  { url: "http://intertwinkles.com", host: "localhost", port: domains.redirect_port },
  { url: "http://d.intr.tw", host: "localhost", port: domains.redirect_port },
  { url: "http://www.intr.tw", host: "localhost", port: domains.redirect_port },
  { url: "http://intr.tw", host: "localhost", port: domains.redirect_port },
  { url: "http://twinkles.media.mit.edu", host: "localhost", port: domains.redirect_port },
  { url: "http://18.85.11.172", host: "localhost", port: domains.redirect_port },
  ]
}
