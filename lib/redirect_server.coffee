http    = require("http")
logger  = require("log4js").getLogger("redirect")

run = (config) ->
  port = config.redirect_port or 9002
  server = http.createServer (req, res) ->
    dest = null
    host = req.headers?.host
    if host?
      if host == "etherpad.intertwinkles.org"
        dest = config.apps.twinklepad.etherpad.url + req.url
      else if host == "dotstorm.intertwinkles.org"
        # Legacy dotstorm URLs.
        dest = config.apps.dotstorm.url + req.url
      else if host == "tenpoints.intertwinkles.org"
        # Legacy tenpoints URLs.
        if req.url == "/" or req.url == ""
          dest = config.apps.points.url + "/"
        else
          dest = config.apps.points.url + "/u" + req.url
      else
        # Plain port 80 redirects.
        dest = config.apps.www.url + req.url
    if dest?
      logger.debug "#{host} => #{dest}"
      res.writeHead(301, {
        "Location": dest
        "Expires":  (new Date).toGMTString()
      })
    else
      logger.debug "Bad request; no host."
      logger.debug req.headers
    res.end()
  logger.info("Logger listening on port " + port + ".")
  server.listen(port)

module.exports = {run}
