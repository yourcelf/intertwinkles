#
# Configuration of proxy server, for resolving public-facing URLs to the
# backend host and etherpad instances.
#
# Launch the proxy server with `cake runproxy`.
#

fs                = require 'fs'
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
  }]
  # HTTPS: Include paths to the key and crt file to enable HTTPS. To use HTTP,
  # comment out this section.  The crt file should contain the whole chain and
  # any intermediaries/root needed for the certificate to validate.
  #https: {
  #  key: fs.readFileSync(__dirname + "/secrets/server.key", 'utf-8').trim()
  #  cert: fs.readFileSync(__dirname + "/secrets/server.crt", 'utf-8').trim()
  #}
}
