#
# This is a proxy based on node-http-proxy which routes requests as specified
# in config/proxy.  It's useful for resolving disparate apps (e.g. etherpad
# and InterTwinkles) running on different domains to their backends.
#
httpProxy = require 'http-proxy'
url       = require 'url'
logger    = require('log4js').getLogger("proxy")

start = (config) ->
  router = {}
  for app in config.routes
    logger.info("#{app.url} => #{app.host}:#{app.port}")
    frontend_parsed = url.parse(app.url)
    router[frontend_parsed.hostname] = "#{app.host}:#{app.port}"

  options = {
    hostnameOnly: true
    router: router
  }
  use_ssl = false
  if config.https?.key and config.https?.cert
    use_ssl = true
    options.https = {
      key: config.https.key
      cert: config.https.cert
    }

  proxyServer = httpProxy.createServer(options)
  proxyServer.listen(config.listen)
  logger.info(
    "#{"SSL enabled. " if use_ssl}Listening for HTTP#{"S" if use_ssl} " +
    "on port #{config.listen}"
  )

module.exports = {start}
