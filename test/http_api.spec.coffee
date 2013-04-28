expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
http          = require 'http'
config        = require './test_config'
schema        = require('../lib/schema').load(config)
common        = require './common'
utils         = require '../lib/utils'
logger        = require('log4js').getLogger()
api_methods   = require("../lib/api_methods")(config)

describe "HTTP api", ->
  before (done) ->
    common.startUp (server) =>
      @server = server
      @browser = common.fetchBrowser()
      done()

  after (done) ->
    common.shutDown(@server, done)

  # Groups API invalid requests
  it "Gets bad request without API key", (done) ->
    url = "http://localhost:#{config.port}/api/groups/?user=one%40mockmyid.com"
    @browser.visit url, (err, browser, status) ->
      expect(status).to.be(400)
      done()

  it "Gets bad request without user", (done) ->
    url = "http://localhost:#{config.port}/api/groups/?api_key=test-key-one"
    @browser.visit url, (err, browser, status) ->
      expect(status).to.be(400)
      done()

  it "Gets permission denied with invalid API key", (done) ->
    url = "http://localhost:#{config.port}/api/groups/?user=one%40mockmyid.com&api_key=invalid"
    @browser.visit url, (err, browser, status) ->
      expect(status).to.be(403)
      done()

  it "Gets permission denied with invalid user", (done) ->
    url = "http://localhost:#{config.port}/api/groups/?user=noexist%40mockmyid.com&api_key=invalid"
    @browser.visit url, (err, browser, status) ->
      expect(status).to.be(403)
      done()

  #
  # Groups API valid request
  #
  it "Gets success with correct user and api key", (done) ->
    url = "http://localhost:#{config.port}/api/groups/?api_key=test-key-one&user=one%40mockmyid.com"
    browser = @browser
    schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) ->
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      browser.visit(url).then( =>
        json = JSON.parse(browser.text())
        # We have our groups...
        expect(_.keys(json.groups).length).to.be(2)
        expect(_.find json.groups, (g) -> g.name == "Two Members").to.not.be(null)
        # And our users...
        expect(json.users[doc.id].email).to.be("one@mockmyid.com")
        # The icons use 'large' and 'small'
        user = json.users[doc.id]
        expect(user.icon.small).to.not.be(null)
        expect(user.icon.sizes).to.be(undefined)
        # Mobile phone numbers are not included.
        expect(user.mobile).to.be(undefined)
        # Groups have 'object id' as their user param
        for id, group of json.groups
          for member in [].concat group.members, group.past_members
            expect(member.user).to.not.be(undefined)
            expect(/^[A-F0-9a-f]+$/.test(member.user)).to.be(true)
          for member in group.invited_members
            expect(member.email).to.be(undefined)
            expect(member.user).to.not.be(undefined)
        done()
      ).fail (err) -> done(err)

  #
  # Email change request
  #
  it "Returns old users authenticating with old addresses unchanged", (done) ->
    api_methods.get_authenticating_user "old_address@mockmyid.com", (err, res) ->
      expect(err).to.be(null)
      {user, message} = res
      expect(user.email).to.be("old_address@mockmyid.com")
      expect(user.email_change_request).to.be("new_address@mockmyid.com")
      expect(message).to.be(undefined)
      done()

  it "Changes email when authenticating with a change_request address", (done) ->
    api_methods.get_authenticating_user "new_address@mockmyid.com", (err, res) ->
      expect(err).to.be(null)
      {user, message} = res
      expect(user.email).to.be("new_address@mockmyid.com")
      expect(user.email_change_request).to.be(null)
      expect(message).to.be("CHANGE_EMAIL")
      done()

  #
  # Create users
  #
  it "Creates a new user when a request comes for a non-existent one", (done) ->
    api_methods.get_authenticating_user "new_user@mockmyid.com", (err, res) ->
      expect(err).to.be(null)
      {user, message} = res
      expect(user.email).to.be("new_user@mockmyid.com")
      expect(typeof user.icon.large).to.be("string")
      expect(message).to.be("NEW_ACCOUNT")
      done()

  it "Edit initial profile", (done) ->
    url = "http://localhost:#{config.port}/api/profiles/"
    schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) ->
      expect(err).to.be(null)
      expect(doc.mobile.number).to.be(null)
      expect(doc.mobile.carrier).to.be(null)

      utils.post_data url, {
        api_key: config.api_key
        user: "one@mockmyid.com"
        icon_id: "7" # barking dog
        icon_color: "00ff00"
        name: "The Stuff"
        mobile_number: "5551234567"
        mobile_carrier: "T-Mobile"
      }, (err, data) ->
        expect(err).to.be(null)
        expect(data.status).to.be(200)
        expect(data.model.name).to.eql("The Stuff")
        expect(data.model.icon.pk).to.eql("7")
        expect(data.model.icon.name).to.eql("Barking Dog")
        expect(data.model.icon.color).to.eql("00FF00")
        expect(data.model.mobile).to.be(undefined)

        schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) ->
          expect(err).to.be(null)
          expect(doc.mobile.number).to.be("5551234567")
          expect(doc.mobile.carrier).to.be("T-Mobile")

          done()

  #
  # Post events
  #
  it "Posts and retrieves an event", (done) ->
    schema.Group.findOne {'slug': 'two-members'}, (err, group) ->
      utils.post_data config.api_url + "/api/events/", {
        event: JSON.stringify({
          application: "firestarter"
          entity: "one"
          type: "create"
          url: "/f/cheese/"
          group: group._id
          data: {test: "data"}
          user: "one@mockmyid.com"
        })
        api_key: config.api_key
      }, (err, data) ->
        logger.error(err) if err?
        expect(err).to.be(null)
        schema.Event.findOne {'application': 'firestarter'}, (err, doc) ->
          expect(doc).to.not.be(null)
          expect(doc.entity).to.eql("one")

          url = config.api_url + "/api/events/"
          utils.get_json url, {
            event: JSON.stringify({application: "firestarter"})
            api_key: config.api_key
          }, (err, data) ->
            expect(err).to.be(null)
            expect(data.events.length).to.be(1)
            expect(data.events[0]._id).to.eql("" + doc._id)
            done()

  it "Refuses posting events with invalid API key", (done) ->
    url = config.api_url + "/api/events/"
    utils.post_data url, {
      event: JSON.stringify({
        application: "firestarter", entity: "one", type: "create",
        url: "/f/cheese/",
        user: "one@mockmyid.com"
      })
      api_key: 'invalid'
    }, (err, data) ->
      expect(err.error).to.eql("Intertwinkles status 403")
      done()

  it "Refuses retrieving events with invalid API key", (done) ->
    url = config.api_url + "/api/events/"
    utils.get_json url, {
      event: JSON.stringify({application: "firestarter"})
      api_key: 'invalid'
    }, (err, data) ->
      expect(err.error).to.eql("Intertwinkles status 403")
      done()

  it "Avoids posting multiple events when timeouts are given", (done) ->
    api_methods = require("../lib/api_methods")(config)
    post_with_timeout = (entity, timeout, cb) ->
      api_methods.post_event {
        application: "firestarter", entity: entity, type: "view"
        url: "/f/fabulous/",
        user: "one@mockmyid.com", anon_id: "some_anon_id"
      }, timeout, (err, event) ->
        expect(err).to.be(null)
        expect(event.entity).to.eql(entity)
        cb()

    async.series([
      # Only the first posts.
      (done) -> post_with_timeout("def", 5000, done),
      (done) -> post_with_timeout("efg", 5000, done),
      (done) -> post_with_timeout("def", 5000, done),
      (done) -> post_with_timeout("efg", 5000, done),
      (done) ->
        schema.Event.find {entity: "def"}, (err, events) ->
          expect(events.length).to.be(1)
          schema.Event.find {entity: "efg"}, (err, events) ->
            expect(events.length).to.be(1)
            done()
      # If we give an undefined timeout, it posts immediately, even if another
      # event with the same signature isn't timed out yet.
      (done) -> post_with_timeout("efg", undefined, done),
      (done) ->
        schema.Event.find {entity: "efg"}, (err, events) ->
          expect(events.length).to.be(2)
          done()
      # If we wait longer than the timeout, it works also.
      (done) -> post_with_timeout("fgh", 50, done),
      (done) -> setTimeout((-> post_with_timeout("fgh", 50, done)), 51)
      (done) ->
        schema.Event.find {entity: "fgh"}, (err, events) ->
          expect(events.length).to.be(2)
          done()
    ], done)

  it "Posts notifications", (done) ->
    url = "http://localhost:#{config.port}/api/notifications/"
    # Add several notifications
    add_notice = (data, cb) ->
      utils.post_data url, {
        api_key: config.api_key
        params: _.extend({
          application: "resolve"
          entity: "one"
          type: "please_respond"
          url: "http://localhost:#{config.port}/f/one"
          recipient: "one@mockmyid.com"
          sender: "two@mockmyid.com"
          formats: {
            web: "Your response is needed for a proposal."
            sms: "Your response is needed for a proposal. http://someurl.com"
            email: {
              subject: "Your response needed"
              body_text: "Here's a proposal, please respond. http://someurl.com"
              body_html: "<p>Here's a proposal, please respond. <a href='http://someurl.com'>http://someurl.com</a></p>"
            }
          }
        }, data)
      }, (err, result) ->
        expect(err).to.be(null)
        notice = result.notifications[0]
        expect(notice.application).to.be("resolve")
        expect(notice.formats.web).to.not.be(null)
        expect(notice.formats.sms).to.not.be(null)
        expect(notice.formats.email.subject).to.not.be(null)
        expect(notice.formats.email.body_text).to.not.be(null)
        expect(notice.formats.email.body_html).to.not.be(null)
        cb()

    async.mapSeries([
      {entity: "one"},
      {entity: "two"},
      {entity: "three"},
      {entity: "four"},
      {recipient: "two@mockmyid.com"}
    ], add_notice, done)

  it "Got the notifications into the DB", (done) ->
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      schema.Notification.find {
        "formats.web": {$ne: null}
        cleared: {$ne: true}
        recipient: user._id
      }, (err, notices) ->
        expect(err).to.be(null)
        expect(notices.length).to.be(4)
        done()

  it "Retrieves notifications", (done) ->
    url = "http://localhost:#{config.port}/api/notifications/"
    utils.get_json url, {
      api_key: config.api_key
      user: "one@mockmyid.com"
    }, (err, result) ->
      expect(err).to.be(null)
      expect(result.notifications.length).to.be(4)
      expect(n.entity for n in result.notifications).to.eql(
        ["four", "three", "two", "one"]
      )
      done()

  it "Clears notifications by ID", (done) ->
    url = "http://localhost:#{config.port}/api/notifications/clear"
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      expect(err).to.be(null)
      schema.Notification.find({recipient: user._id}).sort('date').exec (err, notices) ->
        expect(err).to.be(null)
        expect(notices.length).to.be(4)
        expect(notices[0].entity).to.be("one")

        utils.post_data url, {
          api_key: config.api_key
          user: "one@mockmyid.com"
          notification_id: [notices[0].id, notices[1].id].join(",")
        }, (err, result) ->
          expect(err).to.be(null)
          expect(_.all(n.cleared for n in result.notifications)).to.be(true)
          done()

  it "Clears notifications by application,entity,type", (done) ->
    url = "http://localhost:#{config.port}/api/notifications/clear"
    utils.post_data url, {
      api_key: config.api_key
      application: "resolve"
      entity: "three"
      type: "please_respond"
    }, (err, result) ->
      expect(err).to.be(null)
      expect(result.notifications.length).to.be(1)
      expect(result.notifications[0].entity).to.be("three")
      expect(result.notifications[0].cleared).to.be(true)
      done()

  it "Retrieves uncleared notifications only", (done) ->
    url = "http://localhost:#{config.port}/api/notifications/"
    utils.get_json url, {
      api_key: config.api_key
      user: "one@mockmyid.com"
    }, (err, result) ->
      expect(err).to.be(null)
      expect(result.notifications.length).to.be(1)
      expect(result.notifications[0].entity).to.be("four")
      done()

  it "Suppresses a notification", (done) ->
    get_post_url = "http://localhost:#{config.port}/api/notifications/"
    suppress_url = "http://localhost:#{config.port}/api/notifications/suppress"
    utils.get_json get_post_url, {
      api_key: config.api_key
      user: "one@mockmyid.com"
    }, (err, result) ->
      expect(err).to.be(null)
      expect(result.notifications.length).to.be(1)

      utils.post_data suppress_url, {
        api_key: config.api_key
        user: "one@mockmyid.com"
        notification_id: result.notifications[0]._id
      }, (err, result) ->
        expect(err).to.be(null)
        expect(result.notification.suppressed).to.be(true)
        
        doc = result.notification
        # Update the notification again and see that it is suppressed.
        utils.post_data get_post_url, {
          api_key: config.api_key
          params: {
            application: doc.application
            entity: doc.entity
            type: doc.type
            url: doc.url
            recipient: "one@mockmyid.com"
            sender: "two@mockmyid.com"
            formats: {web: "Nothing doing"}
          }
        }, (err, result) ->
          expect(err).to.be(null)
          expect(result.notifications[0].formats.web).to.be("Nothing doing")

          utils.get_json get_post_url, {
            api_key: config.api_key
            user: "one@mockmyid.com"
          }, (err, result) ->
            expect(err).to.be(null)
            expect(result.notifications.length).to.be(0)
            done()

  it "Posts a search index", (done) ->
    schema.Group.findOne {slug: "two-members"}, (err, group) ->
      expect(err).to.be(null)
      url = config.api_url + "/api/search/"
      utils.post_data url, {
        api_key: config.api_key
        application: "firestarter"
        entity: "123"
        type: "firestarter"
        url: "/f/123"
        title: "Fire!"
        summary: "What's the question, doc? (3 responses)"
        text: "Fire! What's the question, doc? Response 1. Response 2. Response 3."
        sharing: {
          group_id: group.id
        }
      }, (err, result) ->
        expect(err).to.be(null)
        expect(result.searchindex.entity).to.be("123")

        # Ensure that the db has it.
        schema.SearchIndex.find {entity: "123"}, (err, docs) ->
          expect(err).to.be(null)
          expect(docs.length).to.be(1)
          expect(docs[0].absolute_url).to.be(
            "http://localhost:#{config.port}/firestarter/f/123"
          )
          done()

  it "Updates a search index", (done) ->
    schema.Group.findOne {slug: "two-members"}, (err, group) ->
      expect(err).to.be(null)
      url = config.api_url + "/api/search/"
      utils.post_data url, {
        api_key: config.api_key
        application: "firestarter"
        entity: "123"
        type: "firestarter"
        url: "/f/123"
        title: "Fire!"
        summary: "What's the question, doc? (4 responses)"
        text: "Fire! What's the question, doc? Response 1. Response 2. Response 3. Response 4."
        sharing: {
          group_id: group.id
        }
      }, (err, result) ->
        expect(err).to.be(null)
        expect(result.searchindex.entity).to.be("123")
        expect(result.searchindex.summary.indexOf("4 responses")).to.not.be(-1)
        
        # Ensure that we overwrote, not inserted.
        schema.SearchIndex.find {entity: "123"}, (err, docs) ->
          expect(err).to.be(null)
          expect(docs.length).to.be(1)
          expect(docs[0].absolute_url).to.be(
            "http://localhost:#{config.port}/firestarter/f/123"
          )
          done()
    
  it "Removes a search index", (done) ->
    schema.Group.findOne {slug: "two-members"}, (err, group) ->
      expect(err).to.be(null)
      url = config.api_url + "/api/search/"
      utils.post_data url, {
        api_key: config.api_key
        application: "firestarter"
        entity: "123"
        type: "firestarter"
      }, (err, response) ->
        expect(err).to.be(null)
        expect(response.result).to.be("OK")

        schema.SearchIndex.find {entity: "123"}, (err, docs) ->
          expect(err).to.be(null)
          expect(docs.length).to.be(0)
          done()
      , 'DELETE'
  
  it "Posts a twinkle", (done) ->
    schema.User.findOne {email: 'one@mockmyid.com'}, (err, user1) ->
      expect(err).to.be(null)
      schema.User.findOne {email: 'two@mockmyid.com'}, (err, user2) ->
        expect(err).to.be(null)
        post_twinkle = (subentity, sender, recipient, cb) ->
          url = config.api_url + "/api/twinkles/"
          utils.post_data url, {
            api_key: config.api_key
            application: "test"
            entity: "123"
            subentity: subentity
            url: "/test/"
            sender_anon_id: "anon_one"
            sender: sender
            recipient: recipient
          }, (err, results) ->
            expect(err).to.be(null)
            expect(results.twinkle).to.not.be(null)
            expect(results.twinkle.subentity).to.be(subentity)
            cb()
          
        post_twinkle "1", user1._id, user2._id, ->
          schema.Twinkle.find {subentity: "1"}, (err, docs) ->
            expect(docs.length).to.be(1)
            expect(docs[0].sender.toString()).to.be(user1._id.toString())

            post_twinkle "2", null, user2._id, ->
              schema.Twinkle.find {subentity: "2"}, (err, docs) ->
                expect(docs.length).to.be(1)
                expect(docs[0].sender).to.be(null)
                expect(docs[0].recipient.toString()).to.be(user2._id.toString())

                post_twinkle "3", user1._id, null, ->
                  schema.Twinkle.find {subentity: "3"}, (err, docs) ->
                    expect(docs.length).to.be(1)
                    expect(docs[0].sender.toString()).to.be(user1._id.toString())
                    expect(docs[0].recipient).to.be(null)

                    post_twinkle "4", null, null, ->
                      schema.Twinkle.find {subentity: "4"}, (err, docs) ->
                        expect(docs.length).to.be(1)
                        expect(docs[0].sender).to.be(null)
                        expect(docs[0].recipient).to.be(null)
                        done()

  it "Retrieves some twinkles, and removes them", (done) ->
    url = config.api_url + "/api/twinkles/"
    utils.get_json url, {
      api_key: config.api_key, application: "test", entity: "123"
    }, (err, results) ->
      expect(err).to.be(null)
      expect(results.twinkles.length).to.be(4)
      expect(_.map(results.twinkles, (t) -> t.subentity)).to.eql(["1", "2", "3", "4"])

      count = 4

      queue = async.queue (twinkle, done) ->
        url = config.api_url + "/api/twinkles/"
        utils.post_data url, {
          api_key: config.api_key
          twinkle_id: twinkle._id
          sender: twinkle.sender
          sender_anon_id: twinkle.sender_anon_id
        }, (err, results) ->
          expect(err).to.be(null)
          expect(results.result).to.be("OK")
          count -= 1
          schema.Twinkle.find {application: "test", entity: "123"}, (err, docs) ->
            expect(err).to.be(null)
            expect(docs.length).to.be(count)
            done()
        , 'DELETE'
      , 1
      queue.drain = done
      queue.push(results.twinkles)

  it "Creates and resolves short URLs", (done) ->
    url = config.api_url + "/api/shorten/"
    utils.post_data  url, {
      api_key: config.api_key
      application: "firestarter"
      path: "/firestarter/this/is/awesome"
    }, (err, results) ->
      expect(err).to.be(null)
      expect(results.short_url).to.not.be(undefined)
      expect(config.short_url_base).to.be("http://rly.shrt/r")
      expect(
        results.short_url.substring(0, config.short_url_base.length)
      ).to.eql(config.short_url_base)
      short_url_path = results.short_url.substring(config.short_url_base.length)

      http.get({
        hostname: "localhost"
        port: config.port
        path: "/r/#{short_url_path}"
      }, (res) ->
        answer = ''
        res.on 'data', (chunk) -> answer += chunk
        res.on 'end', ->
          expect(res.statusCode).to.be(302)
          expect(res.headers.location).to.be("http://localhost:#{config.port}/firestarter/this/is/awesome")
          done()
      ).on "error", done
