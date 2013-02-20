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

describe "groups", ->
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
        www_methods.create_group @session, params, (err, group) =>
          expect(err).to.be(null)
          expect(group).to.not.be(null)
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
      (user, user2, done) =>
        find_notice = (user, done) =>
          www_schema.Notification.findOne {
            application: "www"
            entity: @group.id
            type: "invitation"
            recipient: user._id
            url: "/groups/join/#{@group.slug}"
            sender: @session.auth.user_id
            cleared: false
          }, (err, doc) =>
            expect(err).to.be(null)
            expect(doc).to.not.be(null)
            done()
        async.map([user, user2], find_notice, done)
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
        www_methods.process_invitation two_session, @group, true, (err) =>
          expect(err).to.be(null)
          schema.Group.findOne {_id: @group._id}, (err, group) =>
            expect(err).to.be(null)
            expect(group.members.length).to.be(2)
            expect(group.invited_members.length).to.be(2)
            found = _.find group.members, (m) ->
              m.user.toString() == two_session.auth.user_id.toString()
            expect(!!found).to.be(true)
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
      }, (err, group) =>
        expect(err).to.be(null)
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
        done()
