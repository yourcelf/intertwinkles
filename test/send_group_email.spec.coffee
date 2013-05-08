_      = require 'underscore'
async  = require 'async'
expect = require 'expect.js'
config = require './test_config'
common = require './common'
schema = require('../lib/schema').load(config)
email_notices = require("../lib/email_notices").load(config)
api_methods = require("../lib/api_methods")(config)
log4js = require("log4js")
logger = log4js.getLogger("socket_server")
logger.setLevel(log4js.levels.FATAL)

describe "Activity summaries", ->
  mail = null
  socket_client = null
  before (done) ->
    common.startUp (server) =>
      @server = server
      common.startMailServer (mailserver) ->
        mail = mailserver
        common.identifiedSockjsClient server, {}, "one@mockmyid.com", (client) ->
          socket_client = client
          done()

  after (done) ->
    socket_client.close()
    common.shutDown(@server, done)

  it "sends email to groups", (done) ->
    mail.outbox.length = 0
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      schema.Group.findOne {slug: "three-members"}, (err, group) ->
        common.stubBrowserID({email: "one@mockmyid.com"})
        session = {}
        api_methods.authenticate session, "assertion", ->
          email_notices.send_custom_group_message session, {
            group_id: group.id
            subject: "Hey there"
            body: "Good times"
          }, (err) ->
            expect(err).to.be(null)
            expect(mail.outbox.length).to.be(1)
            recipients = (a.address for a in mail.outbox[0].to)
            recipients.sort()
            expect(recipients).to.eql(
              ["one@mockmyid.com", "three@mockmyid.com", "two@mockmyid.com"]
            )
            expect(mail.outbox[0].subject).to.be("Hey there")
            expect(mail.outbox[0].text.trim()).to.be("Good times")
            expect(mail.outbox[0].from[0].address).to.be("one@mockmyid.com")
            expect(mail.outbox[0].headers.sender).to.be("notices@example.com")
            done()

  it "doesn't send invalid email", (done) ->
    mail.outbox.length = 0
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      schema.Group.findOne {slug: "three-members"}, (err, group) ->
        schema.Group.findOne {slug: "not-one-members"}, (err, badgroup) ->
          common.stubBrowserID({email: "one@mockmyid.com"})
          session = {}
          api_methods.authenticate session, "assertion", ->
            bads = [{
              # Unauthorized group
              group_id: badgroup.id
              subject: "Hey there"
              body: "Good times"
            }, {
              # Blank group
              subject: "Hey there"
              body: "Good times"
              group_id: ""
            }, {
              # No group
              subject: "Hey there"
              body: "Good times"
            }, {
              # Blank body
              group_id: group.id
              subject: "Hey there"
              body: ""
            }, {
              # No body
              group_id: group.id
              subject: "Hey there"
            }, {
              # Blank subject
              group_id: group.id
              body: "Good times"
              subject: ""
            }, {
              # No subject
              group_id: group.id
              body: "Good times"
            }]
            async.map bads, (bad, done) ->
              email_notices.send_custom_group_message session, bad, (err) ->
                expect(err).to.not.be(null)
                expect(mail.outbox.length).to.be(0)
                done()
            , (err) ->
              # Unauthenticated
              email_notices.send_custom_group_message {}, {
                group_id: group.id
                body: "Good times"
                subject: "Hey there"
              }, (err) ->
                expect(err).to.not.be(null)
                expect(mail.outbox.length).to.be(0)
                done()

  it "sends with a socket message", (done) ->
    mail.outbox.length = 0
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      schema.Group.findOne {slug: "three-members"}, (err, group) ->
        schema.Group.findOne {slug: "not-one-members"}, (err, badgroup) ->
          socket_client.writeJSON {
            route: "email_group",
            body: {
              group_id: group.id
              subject: "Hey there"
              body: "Good times"
            }
          }
          socket_client.onceJSON (data) ->
            expect(mail.outbox.length).to.be(1)
            expect(data.route).to.eql("email_sent")

            mail.outbox.length = 0
            socket_client.writeJSON {
              route: "email_group",
              body: {
                group_id: badgroup.id
                subject: "Hey there"
                body: "Good times"
              }
            }
            socket_client.onceJSON (data2) ->
              expect(mail.outbox.length).to.be(0)
              expect(data2.route).to.be("error")
              done()
