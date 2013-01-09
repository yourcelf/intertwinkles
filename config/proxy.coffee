#
# Configuration of proxy server, for resolving public-facing URLs to the
# backend host and etherpad instances.
#
# Launch the proxy server with `cake runproxy`.
#

domains           = require './domains'
etherpad_settings = require './_read_etherpad_settings'

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
  }]
}
