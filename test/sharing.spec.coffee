expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
config        = require './test_config'
schema        = require('../plugins/www/lib/schema').load(config)
common        = require './common'
intertwinkles = require '../lib/intertwinkles'

describe "sharing", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "Lists group and publicly accessible documents", (done) ->
    async.series [
      (done) =>
        # Grab the user...
        schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) =>
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          @user = doc
          done()
      (done) =>
        # Grab the accessible group...
        schema.Group.findOne {slug: "two-members"}, (err, group) =>
          expect(_.find(group.members, (id) => id == @user._id)).to.not.be(null)
          @memberGroup = group
          done()
      (done) =>
        # Grab the inaccessible group...
        schema.Group.findOne {slug: "not-one-members"}, (err, group) =>
          expect(_.find(group.members, (id) => id == @user._id)).to.be(undefined)
          @notMemberGroup = group
          done()
      (done) =>
        @session = {
          auth: {
            email: @user.email
            user_id: @user.id
          }
          groups: {groups: {}}
        }
        @session.groups[@memberGroup.id] = @memberGroup.toObject()
        done()
      (done) =>
        # Build the test models...
        models = [
          new common.TestModel { name: "explicit_viewer", sharing: {extra_viewers: [@user.email] }}
          new common.TestModel { name: "explicit_editor", sharing: {extra_editors: [@user.email] }}
          new common.TestModel { name: "group_member", sharing: {group_id: @memberGroup._id }}
          new common.TestModel { name: "inaccessible", sharing: {group_id: @notMemberGroup._id }}
          new common.TestModel {
            name: "public_viewing",
            sharing: {
              public_view_until: new Date(3000, 1, 1),
              group_id: @notMemberGroup._id,
              advertise: true
            }
          }
          new common.TestModel {
            name: "public_editing",
            sharing: {
              public_edit_until: new Date(3000, 1, 1),
              group_id: @notMemberGroup._id,
              advertise: true
            }
          }
          new common.TestModel {name: "just_advertise", sharing: {advertise: true}}
        ]
        @models = {}
        save = (m, cb) =>
          m.save (err, doc) =>
            expect(err).to.be(null)
            @models[doc.name] = doc
            cb()
        async.map(models, save, done)
      (done) =>
        common.TestModel.find {}, (err, docs) ->
          expect(docs.length).to.be(7)
          done()
      (done) =>
        # Verify that public documents work..

        intertwinkles.list_public_documents common.TestModel, @session, (err, docs) =>
          doc_names = (doc.name for doc in docs).sort()
          expected_names = ["public_viewing", "public_editing", "just_advertise"].sort()
          expect(doc_names).to.eql(expected_names)
          done()
      (done) =>
        # Verify that group documents work..
        intertwinkles.list_group_documents common.TestModel, @session, (err, docs) =>
          doc_names = (doc.name for doc in docs).sort()
          expected_names = ["explicit_viewer", "explicit_editor", "group_member"].sort()
          expect(doc_names).to.eql(expected_names)
          done()
      (done) =>
        intertwinkles.list_accessible_documents common.TestModel, @session, (err, docs) =>
          expected = {
            group:  ["explicit_viewer", "explicit_editor", "group_member"].sort()
            public: ["public_viewing", "public_editing", "just_advertise"].sort()
          }
          got = {
            group: (doc.name for doc in docs.group).sort()
            public: (doc.name for doc in docs.public).sort()
          }
          expect(got).to.eql(expected)
          done()
    ], done




