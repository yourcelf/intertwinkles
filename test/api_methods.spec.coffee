expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
config        = require './test_config'
schema        = require('../lib/schema').load(config)
common        = require './common'
utils         = require '../lib/utils'
logger        = require('log4js').getLogger()
api_methods   = require("../lib/api_methods")(config)

describe "api", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      done()

  after (done) ->
    common.shutDown(@server, done)

  _check_one_at_mockmyid_users_and_groups = (data) ->
    emails = (u.email for id,u of data.users)
    emails.sort()
    expect(emails).to.eql(
      ["four@mockmyid.com", "one@mockmyid.com", "three@mockmyid.com", "two@mockmyid.com"]
    )
    group_names = (g.name for id,g of data.groups)
    group_names.sort()
    expect(group_names).to.eql(["Three Members", "Two Members"])
  
  it "gets groups", (done) ->
    api_methods.get_groups "one@mockmyid.com", (err, data) ->
      _check_one_at_mockmyid_users_and_groups(data)
      done()

  it "authenticates", (done) ->
    # Stub out mozilla persona, so that we don't need to hit their servers.
    common.stubBrowserID(@browser, {email: "one@mockmyid.com"})
    session = {}
    api_methods.authenticate session, "bogus assertion", (err, session, message) ->
      _check_one_at_mockmyid_users_and_groups(session)
      expect(session.auth.email).to.be("one@mockmyid.com")
      expect(session.auth.user_id).to.not.be(null)
      done()

  it "authenticates user without groups", (done) ->
    common.stubBrowserID(@browser, {email: "no_group@mockmyid.com"})
    session = {}
    api_methods.authenticate session, "bogus assertion", (err, session, message) ->
      expect(session.auth.email).to.be("no_group@mockmyid.com")
      expect(session.auth.user_id).to.not.be(null)
      expect(_.size(session.users)).to.be(1)
      # Iterate into the one user.
      _.each session.users, (user) ->
        expect(user.email).to.be("no_group@mockmyid.com")
        expect(user.icon).to.not.be(null)
      done()

  it "clears session", (done) ->
    common.stubBrowserID(@browser, {email: "one@mockmyid.com"})
    session = {}
    api_methods.authenticate session, "bogus assertion", (err, session, message) ->
      api_methods.clear_session_auth session, (err, session) ->
        expect(session.auth).to.be(null)
        expect(session.groups).to.be(null)
        expect(session.users).to.be(null)
        done()

  it "processes email change requests", (done) ->
    schema.User.findOne {email: "old_address@mockmyid.com"}, (err, old_user) ->
      expect(err).to.be(null)
      expect(old_user).to.not.be(null)
      expect(old_user.email_change_request).to.be("new_address@mockmyid.com")
      api_methods.get_authenticating_user "new_address@mockmyid.com", (err, data) ->
        { user, message } = data
        expect(err).to.be(null)
        expect(user.id).to.be(old_user.id)
        expect(user.email).to.be("new_address@mockmyid.com")
        expect(user.email_change_request).to.be(null)
        expect(message).to.be("CHANGE_EMAIL")
        done()

  it "Events: retrieve", (done) ->
    async.series [
      (done) ->
        api_methods.post_event {
          application: "firestarter"
          entity: "1"
          type: "create"
          user: "one@mockmyid.com"
          data: "This is fun"
        }, done

      (done) ->
        # We can get the one event.
        api_methods.get_events {
          application: "firestarter", entity: "1"
        }, (err, events) ->
          expect(err).to.be(null)
          expect(events.length).to.be(1)
          expect(events[0].data).to.be("This is fun")
          done()

      (done) ->
        # If we filter for something else, we don't get that one event.

        # different app...
        api_methods.get_events {
          application: "resolve", entity: "1"
        }, (err, events) ->
          expect(err).to.be(null)
          expect(events.length).to.be(0)

          # different id.
          api_methods.get_events {
            application: "firestarter", entity: "0"
          }, (err, events) ->
            expect(err).to.be(null)
            expect(events.length).to.be(0)
            done()

      ], (err) ->
        expect(err).to.be(null)
        done()

  it "Events: create", (done) ->
    schema.Group.findOne {name: "Two Members"}, (err, group) ->
      schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
        expect(err).to.be(null)
        expect(group).to.not.be(null)
        api_methods.post_event {
          application: "firestarter"
          entity: "post event test"
          type: "visit"
          user: "one@mockmyid.com" # gets resolved to user id
          group: group.id.toString() # gets resolved to group id
          data: {yup: "fun"}
        }, (err, doc) ->
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          schema.Event.findOne {entity: "post event test"}, (err, doc) ->
            expect(doc.application).to.be("firestarter")
            expect(doc.entity).to.be("post event test")
            expect(doc.type).to.be("visit")
            expect(doc.user).to.eql(user._id)
            expect(doc.group).to.eql(group._id)
            expect(doc.data).to.eql({yup: "fun"})
            done()
          

  it "Events: create with timeout", (done) ->
    _post_event = (data, callback) ->
      api_methods.post_event {
          application: "firestarter"
          entity: "timeouttest"
          type: "visit"
          user: "one@mockmyid.com"
          data: data
        }, 50, callback

    _get_events = (callback) ->
      api_methods.get_events {
        application: "firestarter"
        entity: "timeouttest"
      }, callback

    async.mapSeries [1, 2, 3], _post_event, (err) ->
      expect(err).to.be(null)
      _get_events (err, events) ->
        expect(err).to.be(null)
        expect(events.length).to.be(1)
        expect(events[0].data).to.be(1)
        # After the timeout, it works again.
        setTimeout ->
          _post_event 2, (err) ->
            _get_events (err, events) ->
              expect(events.length).to.be(2)
              data = (e.data for e in events)
              data.sort()
              expect(data).to.eql([1, 2])
              done()
        , 51
