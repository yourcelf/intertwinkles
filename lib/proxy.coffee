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
