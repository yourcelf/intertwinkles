async  = require 'async'
expect = require 'expect.js'
config = require './test_config'
common = require './common'
schema = require('../lib/schema').load(config)
notifier = require("../lib/email_notices").load(config)
intertwinkles = require '../lib/intertwinkles'

describe "Notifications", ->
  mail = null
  before (done) ->
    common.startUp (server, browser, theMail) =>
      @server = server
      @browser = browser
      mail = theMail
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "Sends notifications by email", (done) ->
    async.series [
      (done) ->
        schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
          expect(err).to.be(null)
          user.notifications.invitation.sms = true
          user.notifications.invitation.email = true
          # We don't have a mobile number, so we won't send.
          expect(user.mobile.number).to.be(null)
          user.save(done)
      (done) ->
        schema.Group.findOne {slug: "two-members"}, (err, group) ->
          expect(err).to.be(null)
          intertwinkles.post_notices [{
            application: "www"
            entity: group.id
            type: "invitation"
            recipient: "two@mockmyid.com"
            sender: "one@mockmyid.com"
            url: "/groups/join/#{group.slug}"
            formats: {
              sms: "Test notification"
              email: {
                subject: "Test notification subject"
                text: "This is a textual body"
                html: "<p>My html body</p>"
              }
            }
          }], config, (err, doc) ->
            expect(err).to.be(null)
            done(err)

      (done) ->
        schema.Notification.findSendable {}, (err, docs) ->
          return done(err) if err?
          expect(docs.length).to.be(1)
          n = docs[0]
          expect(n.formats.sms).to.be("Test notification")
          done(null)

      (done) ->
        notifier.send_notifications (err, notices) ->
          return done(err) if err?
          expect(notices.length).to.be(1)
          expect(mail.outbox.length).to.be(1)
          expect(mail.outbox[0].to[0].address).to.be("two@mockmyid.com")
          expect(mail.outbox[0].text).to.be("This is a textual body" + "\n")
          done()

    ], (err) ->
      done(err)

  it "Sends notifications by SMS", (done) ->
    async.series [
      (done) ->
        schema.User.findOne {email: "two@mockmyid.com"}, (err, user) ->
          return done(err) if err?
          user.notifications.needs_my_response.sms = true
          user.notifications.needs_my_response.email = false
          user.mobile.number = "1234567890"
          user.mobile.carrier = "T-Mobile"
          user.save(done)

      (done) ->
        intertwinkles.post_notices [{
          application: "resolve"
          entity: "nonsense"
          type: "needs_my_response"
          recipient: "two@mockmyid.com"
          sender: "one@mockmyid.com"
          url: "/resolve/p/nonsense"
          formats: {
            sms: "Needs yr response"
            email: {
              subject: "Needs yr response subject"
              text: "Needs yr response text"
              html: "<p>Needs yr response body</p>"
            }
          }
        }], config, (err, doc) ->
          expect(err).to.be(null)
          done(err)

      (done) ->
        # Clear the array.
        mail.outbox.length = 0
        notifier.send_notifications (err, notices) ->
          return done(err) if err?
          expect(notices.length).to.be(1)
          expect(mail.outbox.length).to.be(1)
          expect(mail.outbox[0].to[0].address).to.be("1234567890@tmomail.net")
          expect(mail.outbox[0].headers.subject).to.be("Needs yr response")
          expect(mail.outbox[0].text).to.be(" " + "\n\n")
          done()
    ], done

  it "Doesn't send a second time", (done) ->
    mail.outbox.length = 0
    async.series [
      (done) ->
        schema.Notification.findSendable {}, (err, docs) ->
          return done(err) if err?
          expect(docs.length).to.be(0)
          done()

      (done) ->
        notifier.send_notifications (err, notices) ->
          return done(err) if err?
          expect(notices.length).to.be(0)
          expect(mail.outbox.length).to.be(0)
          done()
    ], done

