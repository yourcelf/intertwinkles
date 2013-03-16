# This is a simple SMTP server which can be invoked with a handler callback
# that processes the incoming message.  In addition, messages are stored in
# the module's `outbox` array for later inspection.
#
# Use it for testing and development.
#
# Log mail to the console using:
#
#    start(consoleHandler, [port (or config.email.port)], [started callback])
#

simplesmtp  = require "simplesmtp"
email_conf  = require("../config/config").email
log4js      = require "log4js"
MailParser  = require("mailparser").MailParser

logger = log4js.getLogger()
smtp = null
outbox = []

start = (messageHandler, port, started=(->)) ->
  port = port or email_conf.port
  unless port
    logger.error("Missing port; can't launch SMTP server.")
    process.exit(1)

  smtp = simplesmtp.createServer({disableDNSValidation: true})
  smtp.listen port, (err) ->
    return logger.error(err) if err?
    smtp.on "startData", (envelope) ->
      envelope.parser = new MailParser({defaultCharset: "utf-8"})
      envelope.parser.on "end", (mail) ->
        outbox.push(mail)
        messageHandler(mail)
    smtp.on "data", (envelope, chunk) ->
      envelope.parser.write(chunk)
    smtp.on "dataReady", (envelope, callback) ->
      envelope.parser.end()
      callback(null)
    started()

  return smtp

stop = (callback) ->
  if smtp?
    try
      return smtp.end(callback)
    catch e
      throw e unless e.message == "Not running"
  return callback(null)

consoleHandler = (parsed_message) ->
  logger.log(parsed_message.headers)
  logger.log(parsed_Message.text)

module.exports = {start, stop, consoleHandler, outbox}
