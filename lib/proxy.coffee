#
# This is a proxy based on node-http-proxy which routes requests as specified
# in config/proxy.  It's useful for resolving disparate apps (e.g. etherpad
# and InterTwinkles) running on different domains to their backends.
#
http      = require 'http'
httpProxy = require 'http-proxy'
url       = require 'url'

start = (config) ->
  router = {}
  for app in config.routes
    console.log app.url, "=>", "#{app.host}:#{app.port}"
    frontend_parsed = url.parse(app.url)
    router[frontend_parsed.hostname] = "#{app.host}:#{app.port}"

  proxyServer = httpProxy.createServer({
    hostnameOnly: true
    router: router
  })
  proxyServer.listen(config.listen)

module.exports = {start}
