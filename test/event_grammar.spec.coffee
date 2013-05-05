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

describe "www events grammar", ->
  before (done) ->
    common.startUp (server) =>
      @server = server
      @session = {}
      common.stubBrowserID({email: "one@mockmyid.com"})
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

  group = null

  it "gets terms for an event", (done) ->
    handler = (err, grp, event, notices) ->
      group = grp
      expect(err).to.be(null)
      expect(event).to.not.be(null)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0].entity).to.be("Group")
      expect(terms[0].aspect).to.be('"Fun times"')
      expect(terms[0].collective).to.be("new groups")
      expect(terms[0].verbed).to.be("created")
      expect(terms[0].manner).to.be("")
      done()

    www_methods.create_group @session, {name: "Fun times"}, handler

  it "gets multiple terms for updates", (done) ->
    params = {
      name: "This rocksors"
      member_changeset: {
        update: "one@mockmyid.com": {role: "President"}
        add: {
          "two@mockmyid.com": {voting: false}
          "three@mockmyid.com": {voting: true}
          "four@mockmyid.com": {voting: true}
        }
      }
    }
    www_methods.update_group @session, group, params, (err, grp, event, notices) ->
      group = grp
      expect(err).to.be(null)
      expect(event).to.not.be(null)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(2)
      expect(terms[0]).to.eql({
        entity: "Group \"Fun times\""
        aspect: "name"
        collective: "changed groups"
        verbed: "changed"
        manner: "to \"This rocksors\""
      })
      expect(terms[1]).to.eql({
        entity: "This rocksors"
        aspect: "membership"
        collective: "changed groups"
        verbed: "changed"
        manner: "two@mockmyid.com, three@mockmyid.com, and four@mockmyid.com invited"
      })
      done()

  it "does terms for removal", (done) ->
    params = {member_changeset: {remove: {"two@mockmyid.com": true}}}
    www_methods.update_group @session, group, params, (err, grp, event, notices) ->
      group = grp
      expect(err).to.be(null)
      expect(event).to.not.be(null)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "This rocksors"
        aspect: "membership"
        collective: "changed groups"
        verbed: "changed"
        manner: "two@mockmyid.com removed"
      })
      done()

  it "does terms for decline to join", (done) ->
    session = {}
    common.stubBrowserID({email: "three@mockmyid.com"})
    api_methods.authenticate session, "assertion", (err) ->
      expect(err).to.be(null)
      www_methods.process_invitation session, group, false, (err, group, event, notices) ->
        expect(err).to.be(null)
        expect(event?).to.be(true)
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "This rocksors"
          aspect: "invitation to join"
          collective: "changed groups"
          verbed: "declined"
          manner: ""
        })
        done()

  it "does terms for join", (done) ->
    session = {}
    common.stubBrowserID({email: "four@mockmyid.com"})
    api_methods.authenticate session, "assertion", (err) ->
      expect(err).to.be(null)
      www_methods.process_invitation session, group, true, (err, group, event, notices) ->
        expect(err).to.be(null)
        expect(event).to.not.be(null)
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "This rocksors"
          aspect: "invitation to join"
          collective: "changed groups"
          verbed: "accepted"
          manner: ""
        })
        done()

  it "does terms for logo", (done) ->
    www_methods.update_group @session, group, {
      logo_file: {path: __dirname + "/test_logo.png"}
    }, (err, group, event, notices) ->
      expect(err).to.be(null)
      expect(event).to.not.be(null)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "This rocksors"
        aspect: "logo"
        collective: "changed groups"
        verbed: "added"
        manner: ""
      })
      done()

  it "does terms for logo removal", (done) ->
    www_methods.update_group @session, group, {
      remove_logo: true
    }, (err, group, event, notices) ->
      expect(err).to.be(null)
      expect(event).to.not.be(null)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "This rocksors"
        aspect: "logo"
        collective: "changed groups"
        verbed: "removed"
        manner: ""
      })
      done()
