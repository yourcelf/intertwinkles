expect       = require 'expect.js'
email        = require "emailjs"
email_server = require "../lib/email_server"
config       = require './test_config'

smtp_client = null
check_message_callback = (->)

describe "email", ->
  before (done) ->
    email_server.start( (message) ->
        check_message_callback(message)
      , config.email.port
      , ->
        smtp_client = email.server.connect(config.email)
        done()
    )

  after (done) ->
    email_server.stop(done)

  it "Has the SMTP server and client wired up right.", (done) ->
    message = {
      subject: "Test text message"
      from: "test1@dev.intertwinkles.org"
      to: "test2@dev.intertwinkles.org"
      text: "hello test"
    }
    check_message_callback = (got) ->
      expect(got.text).to.equal(message.text + "\n\n")
      expect(got.headers.subject).to.equal(message.subject)
      expect(got.headers.from).to.equal(message.from)
      expect(got.headers.to).to.equal(message.to)
      expect(email_server.outbox.length).to.be(1)
      expect(email_server.outbox[0]).to.be(got)
      done()

    smtp_client.send(message)
