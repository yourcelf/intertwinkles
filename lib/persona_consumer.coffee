_ = require 'underscore'

default_options =
  protocol: "https"
  host: "verifier.login.persona.org"
  port: 443
  path: '/verify'
  method: 'POST'
  logger:
    debug: (->)

verify = (assertion, audience, callback, options) ->
  # Without the assertion, skip.
  options = _.extend {}, default_options, options
  unless callback? then callback = (->)
  unless assertion? then return callback("Missing assertion")
  if options.protocol == "https"
    httplib = require 'https'
  else if options.protocol == "http"
    httplib = require 'http'
  else
    return callback("Unsupported protocol #{options.protocol}")

  options.logger.debug('browserid verify starting', {assertion, audience})
  # Prepare an http request to the BrowserID verification server
  post_data = JSON.stringify { assertion, audience }
  auth_req_opts =
    host: options.host
    port: options.port
    method: options.method
    path: options.path

  auth_req = httplib.request auth_req_opts, (auth_res) ->
    # Open http connection.
    auth_res.setEncoding('utf8')
    verification_str = ''
    auth_res.on 'data', (chunk) ->
      verification_str += chunk
    auth_res.on 'end', ->
      # Verify response from BrowserID verification server.
      options.logger.debug('browserid response', verification_str)
      answer = JSON.parse(verification_str)
      if answer.status == 'okay' and answer.audience == audience
        options.logger.debug("browserid success: #{answer}")
        callback(null, answer)
      else
        options.logger.debug("browserid fail: #{answer}")
        callback(answer)

  # Write POST data.
  options.logger.debug('browserid contacting server')
  auth_req.setHeader('Content-Type', 'application/json')
  auth_req.setHeader('Content-Length', post_data.length)
  auth_req.write(post_data)
  auth_req.end()

module.exports = { verify }
