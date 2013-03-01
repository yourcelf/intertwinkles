expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
config        = require './test_config'
schema        = require('../lib/schema').load(config)
common        = require './common'
utils         = require '../lib/utils'
logger        = require('log4js').getLogger("test-groups")
www_methods   = require("../lib/www_methods")(config)
www_schema    = require("../lib/schema").load(config)
api_methods   = require("../lib/api_methods")(config)
fs            = require 'fs'
require "better-stack-traces"

describe "www methods", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      @session = {}
      common.stubBrowserID(@browser, {email: "one@mockmyid.com"})
      async.series [
        (done) =>
          www_schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) =>
            @user = doc
            done(err)
        (done) =>
          api_methods.authenticate(@session, "assertion", done)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "Gets user events", (done) ->
    event_params = {
      application: "testy"
      entity: "123"
      type: "test"
      user: @user.id
      group: _.keys(@session.groups)[0]
      date: new Date()
      data: {ok: "whatevs"}
    }
    api_methods.post_event event_params, (err, event) =>
      www_methods.get_user_events @session, (err, events) =>
        expect(events.length).to.be(1)
        evt = events[0].toObject()
        delete evt._id
        delete evt.__v
        evt.user = evt.user.toString()
        evt.group = evt.group.toString()
        expect(evt).to.eql(event_params)
        events[0].remove(done)

  it "Edits profiles", (done) ->
    params = {
      name: "The One"
      email: "new_one@mockmyid.com"
      icon: 42
      color: "ff0088"
      mobile_number: "1234567890"
      mobile_carrier: "T-Mobile"
    }
    www_methods.edit_profile @session, params, (err, user) =>
      expect(err).to.be(null)
      expect(user.name).to.be(params.name)
      expect(user.email).to.be(@user.email)
      expect(user.email_change_request).to.be("new_one@mockmyid.com")
      expect(user.icon.pk).to.be('42')
      expect(user.icon.color).to.be("FF0088")
      expect(user.icon.sizes["16"]).to.be("user_icons/FF0088-Sardines-16.png")
      expect(user.icon.sizes["32"]).to.be("user_icons/FF0088-Sardines-32.png")
      expect(user.icon.sizes["64"]).to.be("user_icons/FF0088-Sardines-64.png")
      expect(user.mobile.number).to.be("1234567890")
      expect(user.mobile.carrier).to.be("T-Mobile")
      www_methods.edit_profile @session, {
        name: @user.name
        email: @user.email
        icon: @user.icon.pk
        color: @user.icon.color
        mobile_number: @user.mobile.number
        mobile_carrier: @user.mobile.carrier
      }, (err, user) =>
        expect(err).to.be(null)
        expect(user.email).to.be(@user.email)
        expect(user.email_change_request).to.be(null)
        done()

  it "Validates profile edit with blank mobile # and carrier", (done) ->
    params = {mobile_number: "", mobile_carrier: ""}
    www_methods.edit_profile @session, params, (err, user) =>
      expect(err).to.be(null)
      expect(user.mobile.number).to.be(null)
      expect(user.mobile.carrier).to.be(null)
      done()

  it "Creates a new group", (done) ->
    params = {
      name: "My Awesome Group"
      member_changeset: {
        update: {
          "one@mockmyid.com": {role: "President"}
        }
        add: {
          "two@mockmyid.com": {voting: false, role: "Two"}
          "three@mockmyid.com": {voting: true, role: "Three"}
          # This one will get created by the invitation.
          "new_user@mockmyid.com": {voting: true, role: "Secretary"}
        }
      }
    }
    async.waterfall [
      (done) =>
        www_schema.User.findOne {email: "new_user@mockmyid.com"}, (err, user) =>
          expect(err).to.be(null)
          expect(user).to.be(null) # great, doesn't exist yet
          done()
      (done) =>
        www_schema.User.findOne {email: "two@mockmyid.com"}, (err, user) =>
          expect(err).to.be(null)
          expect(user).to.not.be(null) # but this one does
          done(null, user)
      (user, done) =>
        www_methods.create_group @session, params, (err, group, event, notices) =>
          expect(err).to.be(null)
          # Get a map of all the users for use in checking recipients of notifications.
          www_schema.User.find {}, (err, docs) =>
            expect(err).to.be(null)
            user_map = {}
            for doc in docs
              user_map[doc.email] = doc._id

            expect(group).to.not.be(null)

            # Check event properties.
            expect(event.type).to.be("create")
            expect(event.application).to.be("www")
            expect(event.entity).to.be(group.id)
            expect(event.user.toString()).to.eql(@session.auth.user_id)
            expect(event.group).to.eql(group._id)
            expect(event.absolute_url).to.eql(
              "http://localhost:#{config.port}/groups/show/my-awesome-group"
            )

            # Check notice properties.
            expect(notices.length).to.be(3)
            user_id = @session.auth.user_id
            expect(n.type for n in notices).to.eql(["invitation", "invitation", "invitation"])
            expect(n.entity for n in notices).to.eql([group.id, group.id, group.id])
            expect(n.sender.toString() for n in notices).to.eql([user_id, user_id, user_id])
            # make a "set" to compare unordered recipients
            recipients = {}
            for n in notices
              recipients[n.recipient.toString()] = true
            expected_recipients = {}
            for e in ["two@mockmyid.com", "three@mockmyid.com", "new_user@mockmyid.com"]
              expected_recipients[user_map[e].toString()] = true
            expect(recipients).to.eql(expected_recipients)

            # Check group properties
            @group = group
            expect(group.isNew).to.be(false)
            expect(group.members.length).to.be(1)
            expect(group.members[0].role).to.be("President")
            expect(group.invited_members.length).to.be(3)
            done(null, user)
      (user, done) =>
        u1 = _.find @group.invited_members, (m) ->
          m.user.toString() == user._id.toString()
        expect(u1).to.not.be(undefined)
        expect(u1.voting).to.eql(false)
        expect(u1.role).to.be("Two")
        done(null, user)
      (user, done) =>
        # This user has now been created.
        www_schema.User.findOne {email: "new_user@mockmyid.com"}, (err, user2) =>
          expect(err).to.be(null)
          expect(user2).to.not.be(null)
          u2 = _.find @group.invited_members, (m) ->
            m.user.toString() == user2._id.toString()
          expect(u2).to.not.be(undefined)
          expect(u2.voting).to.be(true)
          expect(u2.role).to.be("Secretary")
          done(null, user, user2)
          @new_user = user2
    ], done

  it "Processes invitations", (done) ->
    two_session = {}
    three_session = {}
    async.series [
      (done) =>
        # Authenticate two@mockmyid.com and three@mockmyid.com sessions.
        authenticate = (props, done) =>
          [email, session] = props
          common.stubBrowserID(@browser, {email})
          api_methods.authenticate session, "assertion", (err) =>
            expect(err).to.be(null)
            expect(session.auth.user_id).to.not.be(undefined)
            done()
        async.map [
          ["two@mockmyid.com", two_session],
          ["three@mockmyid.com", three_session]
        ], authenticate, done
      (done) =>
        # Have two@mockmyid.com accept the invitation.
        www_methods.process_invitation two_session, @group, true, (err, group, event, notices) =>
          expect(err).to.be(null)
          # Group details
          expect(group).to.not.be(null)
          expect(group.members.length).to.be(2)
          expect(group.invited_members.length).to.be(2)
          found = _.find group.members, (m) ->
            m.user.toString() == two_session.auth.user_id.toString()
          expect(!!found).to.be(true)

          # Event details
          expect(event).to.not.be(null)
          expect(event.type).to.be("join")
          expect(event.user.toString()).to.be(two_session.auth.user_id)
          expect(event.group).to.eql(group._id)

          # Notice details
          expect(notices.length).to.be(1)
          n = notices[0]
          expect(n.type).to.be("invitation")
          expect(n.cleared).to.be(true)
          expect(n.recipient.toString()).to.be(two_session.auth.user_id)

          done()
      (done) =>
        # Have three@mockmyid.com refuse the invitation.
        www_methods.process_invitation three_session, @group, false, (err) =>
          expect(err).to.be(null)
          schema.Group.findOne {_id: @group._id}, (err, group) =>
            expect(err).to.be(null)
            expect(group).to.not.be(null)
            expect(group.members.length).to.be(2)
            expect(group.invited_members.length).to.be(1)
            found = _.find group.members, (m) ->
              m.user.toString() == three_session.auth.user_id.toString()
            expect(found).to.be(undefined)
          done()
      (done) =>
        # There should no longer be invitation notifications for either
        # two@mockmyid.com or three@mockmyid.com (just one for
        # new_user@mockmyid.com).
        www_schema.Notification.find {
          application: "www"
          entity: @group.id
          type: "invitation"
          cleared: false
        }, (err, docs) =>
          expect(err).to.be(null)
          expect(docs.length).to.be(1)
          expect(docs[0].recipient.toString()).to.eql(@new_user._id.toString())
          done()
    ], done

  it "Updates a group", (done) ->
    # Make sure we have the latest changes, refetch.
    schema.Group.findOne {_id: @group._id}, (err, group) =>
      www_methods.update_group @session, group, {
        name: "A New Name"
        member_changeset: {
          update: {
            "one@mockmyid.com": {role: "Fool", voting: true}
          }
          remove: {
            "two@mockmyid.com": true # an existing member
            "new_user@mockmyid.com": true    # an invitee
          }
          add: {
            "four@mockmyid.com": {role: "Muahaha", voting: false}
          }
        }
      }, (err, group, event, notices) =>
        www_schema.User.find {}, (err, docs) =>
          expect(err).to.be(null)
          # Get a map of all users to check recipients with
          user_map = {}
          for doc in docs
            user_map[doc.email] = doc._id

          expect(err).to.be(null)
          # Group properties
          expect(group).to.not.be(null)
          expect(group.members.length).to.be(1)
          expect(group.members[0].role).to.be("Fool")
          expect(group.invited_members.length).to.be(1)
          expect(group.invited_members[0].role).to.be("Muahaha")
          expect(group.past_members.length).to.be(1)
          expect(group.past_members[0].role).to.be("Two")
          expect(group.past_members[0].removed_by.toString()).to.eql(
            @session.auth.user_id.toString()
          )
          @group = group

          # Event properties
          expect(event).to.not.be(null)
          expect(event.type).to.be("update")
          expect(event.application).to.be("www")
          expect(event.user.toString()).to.eql(@session.auth.user_id)

          # Notifications
          expect(notices.length).to.be(2)
          oldn = _.find(notices, (n) -> n.cleared == true)
          newn = _.find(notices, (n) -> n.cleared == false)
          expect(oldn.recipient).to.eql(user_map["new_user@mockmyid.com"])
          expect(newn.recipient).to.eql(user_map["four@mockmyid.com"])
          expect(n.type for n in notices).to.eql(["invitation", "invitation"])
          done()

  it "Uploads a file", (done) ->
    www_methods.update_group @session, @group, {
      logo_file: __dirname + "/test_logo.png"
    }, (err, group, event, notices) =>
      expect(err).to.be(null)
      prefix = __dirname + "/../uploads/"
      expect(fs.existsSync(prefix + group.logo.full)).to.be(true)
      expect(fs.existsSync(prefix + group.logo.thumb)).to.be(true)
      # original still there
      expect(fs.existsSync(__dirname + "/test_logo.png")).to.be(true)
      fs.unlinkSync(prefix + group.logo.full)
      expect(fs.existsSync(prefix + group.logo.full)).to.be(false)
      fs.unlinkSync(prefix + group.logo.thumb)
      expect(fs.existsSync(prefix + group.logo.thumb)).to.be(false)

      expect(event).to.not.be(null)
      expect(event.type).to.be("update")
      expect(notices.length).to.be(0)

      done()
