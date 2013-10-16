expect        = require 'expect.js'
_             = require 'underscore'
http          = require 'http'
config        = require './test_config'
common        = require './common'
libxmljs      = require 'libxmljs'
async         = require 'async'

api_methods = require('../lib/api_methods')(config)
hangout_methods = require('../lib/hangout_methods')(config)
schema = require("../lib/schema").load(config)
# Use resolve proposal as test doc.
resolvelib = require("../plugins/resolve/lib/resolve")(config)

describe "Hangout", ->
  server = null
  session = {}
  session2 = {}
  doc = null
  client = null
  client2 = null

  before (done) ->
    async.series [
      (done) ->
        # Start the web server
        common.startUp (theServer) ->
          server = theServer
          done()
      (done) ->
        # Build a sockjs client and session.
        common.identifiedSockjsClient server, session, "one@mockmyid.com", (theClient) ->
          client = theClient
          done()

      (done) ->
        # Authenticate another session.
        common.identifiedSockjsClient server, session2, "three@mockmyid.com", (theClient) ->
          client2 = theClient
          done()

      (done) ->
        # Create a document to use, owned by one of our groups.
        # Use resolve for our test docs.
        schema.Group.findOne {slug: "two-members"}, (err, group) ->
          expect(err).to.be(null)
          resolvelib.create_proposal session, {proposal: {
            sharing: {group_id: group.id}
            proposal: "This is fun"
            name: "Ok"
          }}, (err, prop) ->
            expect(err).to.be(null)
            doc = prop
            done()
    ], (err) ->
      expect(err).to.be(null)
      done()

  after (done) ->
    common.shutDown server, ->
      client.close()
      client2.close()
      done()

  get_http_response = (url, callback) ->
    http.get url, (res) ->
      data = ''
      res.on 'data', (chunk) -> data += chunk
      res.on 'end', ->
        callback(null, res.statusCode, data)
    .on 'error', (e) ->
      callback(e)

  it "Publishes gadget xml file", (done) ->
    get_http_response "http://localhost:#{config.port}/hangout/gadget.xml", (err, status, data) ->
      expect(err).to.be(null)
      expect(status).to.be(200)
      xml = libxmljs.parseXml(data)
      expect(xml.get('//ModulePrefs').attr('title').value()).to.be("InterTwinkles")
      done()

  it "Publishes front page", (done) ->
    get_http_response "http://localhost:#{config.port}/hangout/", (err, status, data) ->
      expect(err).to.be(null)
      expect(status).to.be(200)
      done()

  it "Validates hangout document URLs with relative paths", (done) ->
    # Show that /relative/paths fail.
    hangout_methods.validate_url session, doc.url, (err, urlinfo) ->
      expect(err).to.be(null)
      expect(urlinfo).to.eql({request_url: doc.url, valid: false})
      done()


  it "Validates hangout document URLs with empty paths", (done) ->
    # Show that empty string fails.
    hangout_methods.validate_url session, "", (err, urlinfo) ->
      expect(err).to.be(null)
      expect(urlinfo).to.eql({request_url: "", valid: false})
      done()

  it "Validates hangout document URLs with full paths", (done) ->
    hangout_methods.validate_url session, doc.absolute_url, (err, urlinfo) ->
      expect(err).to.be(null)
      expect(urlinfo.request_url).to.be(doc.absolute_url)
      expect(urlinfo.valid).to.be(true)
      expect(urlinfo.doc.absolute_url).to.be(doc.absolute_url)
      done()

  it "Validates hangout document URLs with short URLs", (done) ->
    api_methods.make_short_url doc.absolute_url, "resolve", (err, surl) ->
      hangout_methods.validate_url session, surl.absolute_short_url, (err, urlinfo) ->
        expect(err).to.be(null)
        expect(urlinfo.request_url).to.be(surl.absolute_short_url)
        expect(urlinfo.valid).to.be(true)
        expect(urlinfo.doc.absolute_url).to.be(doc.absolute_url)
        done()

  it "Validates hangout document URLs with unauthenticated session", (done) ->
    hangout_methods.validate_url {}, doc.absolute_url, (err, urlinfo) ->
      expect(err).to.be(null)
      expect(urlinfo).to.eql({
        request_url: doc.absolute_url
        valid: false
      })
      done()

  it "Validates hangout document URLs with authenticated, unauthorized session", (done) ->
    hangout_methods.validate_url session2, doc.absolute_url, (err, urlinfo) ->
      expect(err).to.be(null)
      expect(urlinfo).to.eql({
        request_url: doc.absolute_url
        valid: false
      })
      done()

  it "Cleans room docs", ->
    # Build a few mock mongoose objects with sharing properties.
    mk_owned_by_session = ->
      return {
        title: "fun"
        sharing: {
          group_id: doc.sharing.group_id
          public_view_until: undefined
          public_edit_until: undefined
          advertise: undefined
        }
        absolute_url: "http://absolutely"
        toJSON: ->
          clone = mk_owned_by_session()
          delete clone.toJSON
          return clone
      }
    mk_owned_by_other = ->
      return {
        title: "fun"
        sharing: {
          group_id: "somethingelse"
          public_view_until: undefined
          public_edit_until: undefined
          advertise: undefined
        }
        absolute_url: "http://absolutely"
        toJSON: ->
          clone = mk_owned_by_other()
          delete clone.toJSON
          return clone
      }
    mk_viewable_by_other_but_dirty = ->
      return {
        title: "fun"
        sharing: {
          group_id: "somethingelse"
          public_view_until: new Date("2050-01-01T12:00:00Z") # Far future
          public_edit_until: null
          extra_editors: ["secret1@example.com", "secret2@example.com"]
          extra_viewers: ["secret3@example.com", "secret4@example.com"]
          advertise: undefined
        }
        absolute_url: "http://absolutely"
        toJSON: ->
          clone = mk_viewable_by_other_but_dirty()
          delete clone.toJSON
          return clone
      }
    owned_by_session = mk_owned_by_session()
    owned_by_other = mk_owned_by_other()
    viewable_by_other_but_dirty = mk_viewable_by_other_but_dirty()

    # We can view the whole thing unchanged.
    expect(hangout_methods.clean_room_docs(session, [owned_by_session])).to.eql(
      [owned_by_session.toJSON()]
    )
    # We can't view this doc at all -- so all we get is the URL.
    expect(hangout_methods.clean_room_docs(session, [owned_by_other])).to.eql(
      [{absolute_url: owned_by_other.absolute_url}]
    )
    # We can view this doc, but not all of its sharing properties.
    copy = viewable_by_other_but_dirty.toJSON()
    delete copy.sharing.extra_editors
    delete copy.sharing.extra_viewers
    expect(hangout_methods.clean_room_docs(session, [viewable_by_other_but_dirty])).to.eql(
      [copy]
    )

  it "Socket methods in one big go", (done) ->
    # This should really be split out into separate tests -- but it's one big
    # method here so that we can avoid having to re-build the room over and
    # over again. Maybe a refactor some time could split this out into a
    # separate test case, to avoid the re-creating of the room slowing down
    # each prior test.

    # Both of our clients join the room.
    joined = []
    async.mapSeries [client, client2], (client, done) ->
      client.writeJSON {route: "join", body: {room: "hangout/test"}}
      joined.push(client)
      async.series [
        (done) ->
          client.onceJSON (data) ->
            expect(data.route).to.be("hangout:document_list")
            expect(data.body).to.eql({hangout_docs: []})
            done()
        (done) ->
          client.onceJSON (data) ->
            expect(data.route).to.be("join")
            done()
        (done) ->
          async.map joined, (client, done) ->
            client.onceJSON (data) ->
              expect(data.route).to.be("room_users")
              done()
          , done
      ], done
    , (err) ->
      # Both clients should now have joined.
      expect(err).to.be(null)

      async.series [
        (done) ->
          # Client1, who has perms for it, adds doc.
          client.writeJSON {
            route: "hangout/add_document",
            body: {
              room: "hangout/test"
              request_url: doc.absolute_url
            }
          }
          # Both clients receive a document_list response.
          async.parallel [
            (done) ->
              # Client1 gets the whole doc, cause it has perms.
              client.onceJSON (data) ->
                expect(data.route).to.be("hangout:document_list")
                expect(data.body.hangout_docs.length).to.be(1)
                expect(data.body.hangout_docs[0].title).to.eql(doc.title)
                expect(data.body.hangout_docs[0].absolute_url).to.eql(doc.absolute_url)
                done()
            (done) ->
              # Client2 lacks perms, so just gets the URL.
              client2.onceJSON (data) ->
                expect(data.route).to.be("hangout:document_list")
                expect(data.body.hangout_docs.length).to.be(1)
                expect(data.body.hangout_docs[0].id).to.be(undefined)
                expect(data.body.hangout_docs[0].title).to.be(undefined)
                expect(data.body.hangout_docs[0].absolute_url).to.eql(doc.absolute_url)
                done()
          ], done

        (done) ->
          # Test validating invalid URL over socket.
          client.writeJSON {
            route: "hangout/validate_url",
            body: {
              request_url: "invalid"
            }
          }
          client.onceJSON (data) ->
            expect(data.route).to.be("hangout:validate_url")
            expect(data.body).to.eql({request_url: "invalid", valid: false})
            done()

        (done) ->
          # Test validating valid URL over soccket.
          client.writeJSON {
            route: "hangout/validate_url",
            body: {
              request_url: doc.absolute_url
            }
          }
          client.onceJSON (data) ->
            expect(data.route).to.be("hangout:validate_url")
            expect(data.body.request_url).to.eql(doc.absolute_url)
            expect(data.body.valid).to.be(true)
            expect(data.body.doc).to.not.be(undefined)
            expect(data.body.doc.title).to.be(doc.title)
            done()

        (done) ->
          # Test validating unauthorized URL over socket.
          client2.writeJSON {
            route: "hangout/validate_url"
            body: { request_url: doc.absolute_url }
          }
          client2.onceJSON (data) ->
            expect(data.route).to.be("hangout:validate_url")
            expect(data.body.request_url).to.be(doc.absolute_url)
            expect(data.body.valid).to.be(false)
            expect(data.body.doc).to.be(undefined)
            done()

        (done) ->
          # Test list user documents over socket.
          client.writeJSON {route: "hangout/list_user_documents"}
          client.onceJSON (data) ->
            expect(data.route).to.be("hangout:user_documents")
            expect(data.body.docs.length).to.be(1)
            expect(data.body.docs[0].absolute_url).to.eql(doc.absolute_url)
            done()

        (done) ->
          # Test list user documents (when you have none) over socket.
          client2.writeJSON {route: "hangout/list_user_documents"}
          client2.onceJSON (data) ->
            expect(data.route).to.be("hangout:user_documents")
            expect(data.body.docs.length).to.be(0)
            done()

        (done) ->
          # Test clear list of hangout docs on leaving a room.
          async.series [
            (done) ->
              # Client 1 leaves
              client.writeJSON {route: "leave", body: {room: "hangout/test"}}
              async.parallel [
                (done) ->
                  client.onceJSON (data) ->
                    expect(data.route).to.be("leave")
                    done()
                (done) ->
                  client2.onceJSON (data) ->
                    expect(data.route).to.be("room_users")
                    done()
              ], done

            (done) ->
              # Client 2 leaves. Room is now empty.
              client2.writeJSON {route: "leave", body: {room: "hangout/test"}}
              client2.onceJSON (data) ->
                expect(data.route).to.be("leave")
                expect(data.body.last).to.be(true)
                done()

            (done) ->
              # Client 1 returns. Document list is now empty.
              client.writeJSON {route: "join", body: {room: "hangout/test"}}
              async.series [
                (done) ->
                  client.onceJSON (data) ->
                    expect(data.route).to.be("hangout:document_list")
                    expect(data.body.hangout_docs.length).to.be(0)
                    done()
                (done) ->
                  client.onceJSON (data) ->
                    expect(data.route).to.be("join")
                    done()
                (done) ->
                  client.onceJSON (data) ->
                    expect(data.route).to.be("room_users")
                    done()
              ], done
          ], done
      ], (err) ->
        expect(err).to.be(null)
        done()
