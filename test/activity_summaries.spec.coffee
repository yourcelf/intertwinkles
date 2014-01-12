_      = require 'underscore'
async  = require 'async'
expect = require 'expect.js'
config = require './test_config'
common = require './common'
schema = require('../lib/schema').load(config)
email_notices = require("../lib/email_notices").load(config)
api_methods = require("../lib/api_methods")(config)
email_invitation_view = require("../emails/invitation")

describe "Activity summaries", ->
  mail = null
  before (done) ->
    common.startUp (server) =>
      @server = server
      common.startMailServer (mailserver) ->
        mail = mailserver
        done()

  after (done) ->
    common.shutDown(@server, done)

  it "sends nothing with no activity", (done) ->
    mail.outbox.length = 0
    email_notices.send_daily_activity_summaries (err, count) ->
      expect(err).to.be(null)
      expect(count).to.be(0) # two people (members of two-members)
      expect(mail.outbox.length).to.be(0) # one sms, two emails
      done()

  it "renders summary", (done) ->
    async.waterfall [
      (done) ->
        schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
          expect(err).to.be(null)
          user.notifications.activity_summaries.sms = true
          user.notifications.activity_summaries.email = true
          user.mobile.number = "1234567890"
          user.mobile.carrier = "T-Mobile"
          user.save (err, doc) ->
            done(err, doc)
      (user, done) ->
        schema.Group.findOne {slug: "two-members"}, (err, group) ->
          expect(err).to.be(null)
          api_methods.post_event {
            application: "www"
            entity: group._id
            type: "join"
            user: user
            group: group._id
            anon_id: "anon"
            url: group.url
            data: {entity_name: group.name}
          }, (err, event) ->
            done(err, user, group, event)

      (user, group, event, done) ->
        email_notices.render_daily_activity_summary user, new Date(), (err, formats) ->
          expect(err).to.be(null)
          expect(formats).to.not.be(null)
          sms = "Recent InterTwinkles activity: 1 edit #{config.short_url_base}"
          expect(formats.sms.substring(0, sms.length)).to.be(sms)
          expect(formats.email.subject).to.not.a(String)
          expect(formats.email.text).to.not.a(String)
          expect(formats.email.html).to.not.a(String)
          done()

    ], done

  it "sends email", (done) ->
    mail.outbox.length = 0
    email_notices.send_daily_activity_summaries (err, count) ->
      expect(err).to.be(null)
      expect(count).to.be(3) # one sms, two emails
      common.await ->
        if mail.outbox.length == 3
          recipients = (m.to[0].address for m in mail.outbox)
          recipients.sort()
          expect(recipients).to.eql(
            ["1234567890@tmomail.net", "one@mockmyid.com", "two@mockmyid.com"]
          )
          done()
          return true
      
  it "doesn't send if there's preference not to", (done) ->
    mail.outbox.length = 0
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      expect(err).to.be(null)
      user.notifications.activity_summaries.email = false
      # Sending SMS blocked by missing a mobile number. User gets no
      # notification.
      user.notifications.activity_summaries.sms = true
      user.mobile.number = null
      user.mobile.carrier = null
      user.save (err, user) ->

        expect(err).to.be(null)
        email_notices.send_daily_activity_summaries (err, count) ->
          expect(err).to.be(null)
          expect(count).to.be(1)
          common.await ->
            return false unless mail.outbox.length == 1
            recipients = (m.to[0].address for m in mail.outbox)
            expect(recipients).to.eql(["two@mockmyid.com"])

            mail.outbox.length = 0
            # Re-add SMS address, this time it should send, as the user still has
            # a preference for it to be sent via SMS.  But no email still.
            user.mobile.number = "1234567890"
            user.mobile.carrier = "T-Mobile"
            user.save (err, user) ->
              expect(err).to.be(null)
              email_notices.send_daily_activity_summaries (err, count) ->
                expect(err).to.be(null)
                expect(count).to.be(2)
                common.await ->
                  return false unless mail.outbox.length == 2
                  recipients = (m.to[0].address for m in mail.outbox)
                  recipients.sort()
                  expect(recipients).to.eql(
                    ["1234567890@tmomail.net", "two@mockmyid.com"]
                  )
                  done()
                  return true
            return true
  
  it "doesn't send bare invitations", (done) ->
    # We don't want to spam users who have been invited (perhaps without their
    # desire) any more than once ever. By default, a new user will get an email
    # when they are invited to join a group.  That should be the last email
    # they receive until they accept the invite.
    mail.outbox.length = 0
    schema.Event.remove {}, (err) ->
      schema.Group.findOne {slug: "three-members"}, (err, group) ->
        schema.User.findOne {email: "one@mockmyid.com"}, (err, sender) ->
          schema.User.findOne {email: "four@mockmyid.com"}, (err, recipient) ->
            email_notices.render_notifications email_invitation_view, {
              group: group
              sender: sender
              recipient: recipient
              url: config.api_url + "/groups/join/#{group.slug}"
              application: "www"
            }, (err, rendered) ->
              api_methods.post_notifications [{
                application: "www"
                type: "invitation"
                entity: group.id
                recipient: recipient.id
                url: "/groups/join/#{group.slug}"
                sender: sender.id
                formats: rendered
              }], (err, notices) ->
                email_notices.send_daily_activity_summaries (err, count) ->
                  expect(err).to.be(null)
                  expect(count).to.be(0)
                  expect(mail.outbox.length).to.be(0)
                  done()
