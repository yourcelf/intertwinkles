#
# NOTE: This file is not run automatically with `npm test`, as it doesn't work
# unless you install solr with the schema and have it running. To run these
# tests, start solr and install solr_schema.xml as the solr's `schema.xml`, and
# then:
#
#   mocha --compilers coffee:coffee-script --globals css,js,img test/solr.coffee
#

intertwinkles = require '../lib/intertwinkles'
expect        = require 'expect.js'
async         = require 'async'
_             = require 'underscore'

common        = require './common'
config        = require './test_config'
schema        = require('../lib/schema').load(config)
solr_client   = require('solr-client').createClient(config.solr)

clear_test_docs_from_solr = (done) ->
  #return done()
  # Try it with the api first.
  url = config.api_url + "/api/search/"
  intertwinkles.post_data url, {
    api_key: config.api_key
    entity: "test1"
    application: "test"
    type: "test"
  }, (err) ->
    expect(err).to.be(null)

    # Now jump to the client directly, so we can do a more permissive mass
    # deletion that we would never do in production.
    solr_client.delete 'application', 'test', (err, obj) ->
      expect(err).to.be(null)

      # Force commit.
      solr_client.commit {}, (err, obj) ->
        expect(err).to.be(null)
        
        # Ensure we're empty.
        solr_client.search "q=application%3Atest", (err, obj) ->
          expect(err).to.be(null)
          expect(obj.response.numFound).to.be(0)
          done()
  , 'DELETE'

describe "solr search", ->
  before (done) ->
    if process.env.SKIP_SOLR_TESTS
      return done()
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      clear_test_docs_from_solr(done)

  after (done) ->
    if process.env.SKIP_SOLR_TESTS
      return done()
    clear_test_docs_from_solr (err) =>
      common.shutDown(@server, done)

  it "Posts and retrieves documents via api", (done) ->
    api_methods = require("../lib/api_methods")(config)
    if process.env.SKIP_SOLR_TESTS
      return done()
    api_methods.add_search_index {
      application: "test"
      entity: "test1"
      type: "test"
      url: "/fun"
      title: "This is a test"
      summary: "This is only a test"
      text: "This is a test this is only a test dial 123"
      sharing: {
        group_id: ""
        public_view_until: new Date(3000,1,1)
        public_edit_until: null
        sharing_extra_viewers: []
        sharing_extra_editors: []
        advertise: true
      }
    }, (err, result) ->
      expect(err).to.be(null)
      expect(result.entity).to.be("test1")

      solr_client.commit {}, (err, obj) ->
        expect(err).to.be(null)

        async.map [
          {q: "dial", public: true}
          {application: "test", public: true}
          {entity: "test1", public: true}
          {type: "test", public: true}
          {application: "test", type: "test", entity: "test1", public: true}
        ], (query, done) ->
          url = config.api_url + "/api/search/"
          query.api_key = config.api_key
          intertwinkles.get_json url, query, (err, result) ->
            expect(err).to.be(null)
            expect(result.responseHeader.status).to.be(0)
            expect(result.response.numFound).to.be(1)
            expect(result.response.docs[0].entity).to.be("test1")
            done()
        , (err) ->
          expect(err).to.be(null)
          done()

  it "Constrains based on sharing", (done) ->
    if process.env.SKIP_SOLR_TESTS
      return done()
    api_methods = require("../lib/api_methods")(config)
    schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
      expect(err).to.be(null)
      expect(user).to.not.be(null)

      schema.Group.find {"members.user": user._id}, (err, groups) ->
        expect(err).to.be(null)
        expect(groups.length).to.not.be(0)

        # Build a set of search indexes with different sharing options.
        default_doc = {
          application: "test", type: "test", url: "/test",
          title: "This is a test", summary: "This is only a test",
          text: "This is a test this is only a test furby 123",
        }
        test_docs = {
          group_owned: { group_id: groups[0].id }
          other_group_owned: { group_id: "xxx" }
          extra_viewer: {
            group_id: "xxx"
            extra_viewers: ["one@mockmyid.com"]
          }
          extra_editor: {
            group_id: "xxx"
            extra_editors: ["one@mockmyid.com"]
          }
          public_no_advertise: {
            group_id: "xxx", public_edit_until: new Date(3000,1,1), advertise: false
          }
          public_edit_advertise: {
            group_id: "xxx", public_edit_until: new Date(3000,1,1), advertise: true
          }
          public_view_advertise: {
            group_id: "xxx", public_view_until: new Date(3000,1,1), advertise: true
          }
        }
        defs = (_.extend({sharing, entity}, default_doc) for entity,sharing of test_docs)
        async.map defs, (def, done) ->
          api_methods.add_search_index(def, done)
        , (err, results) ->
          solr_client.commit (err, obj) ->
            expect(err).to.be(null)
            docs = {}
            for result in results
              docs[result.entity] = result

            solr = require("../lib/solr_helper")(config)
            expect_docs = (params, done) ->
              {query, expected} = params
              solr.execute_search query, query.user, (err, results) ->
                expect(err).to.be(null)
                found = {}
                wanted = {}
                for doc in results.response.docs
                  found[doc.entity] = true
                for entity in expected
                  wanted[entity] = true
                expect(found).to.eql(wanted)
                done()

            # Search by user, ensuring that we can only see the ones we should.
            async.map [
              {
                query: {user: "one@mockmyid.com", q: "furby" },
                expected: ["group_owned", "extra_viewer", "extra_editor"]
              },
              {
                query: {user: "one@mockmyid.com", public: false, q: "furby" },
                expected: ["group_owned", "extra_viewer", "extra_editor"]
              },
              {
                query: {user: "one@mockmyid.com", public: true, q: "furby" },
                expected: [
                  "group_owned", "extra_viewer", "extra_editor",
                  "public_edit_advertise", "public_view_advertise",
                ]
              },
              {
                query: {user: "one@mockmyid.com", public: true, q: "not theyar" },
                expected: []
              },
              {
                query: {user: "one@mockmyid.com", public: true, q: "<script>-+&|!(){}[]^\"~*?:\\</script>" },
                expected: []
              }
            ], expect_docs, (err) ->
              expect(err).to.be(null)
              done()
