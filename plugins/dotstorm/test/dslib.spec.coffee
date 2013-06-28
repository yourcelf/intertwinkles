fs          = require 'fs'
expect      = require 'expect.js'
_           = require 'underscore'
async       = require 'async'
config      = require '../../../test/test_config'
common      = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema  = require('../../../lib/schema').load(config)
ds_schema   = require("../lib/schema").load(config)
dslib   = require("../lib/dslib")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

describe "dslib", ->
  all_users = {}
  all_groups = {}
  session = {}
  session2 = {}
  server = null

  before (done) ->
    common.startUp (theserver) ->
      server = theserver
      async.series [
        (done) ->
          # get all users and groups for convenience
          common.getAllUsersAndGroups (err, maps) ->
            all_users = maps.users
            all_groups = maps.groups
            done()
        (done) ->
          # Establish a session.
          session = {}
          common.stubBrowserID({email: "one@mockmyid.com"})
          api_methods.authenticate session, "mock assertion", ->
            session.anon_id = "anon_id_1"
            done()
        (done) ->
          session2 = {}
          common.stubBrowserID({email: "two@mockmyid.com"})
          api_methods.authenticate session2, "mock assertion", ->
            session2.anon_id = "anon_id_2"
            done()

      ], done

  after (done) ->
    common.shutDown(server, done)

  _no_err_args = (args) ->
    expect(args[0]).to.be(null)
    for i in [1...args.length]
      expect(args[i]).to.not.be(null)
      expect(args[i]).to.not.be(undefined)

  it "Errors with invalid params", (done) ->
    dslib.create_dotstorm session, {this_is_not: "valid"}, (err, doc, event, si) ->
      expect(err).to.be("Missing param")
      done()

  it "creates a dotstorm", (done) ->
    dslib.create_dotstorm session, {
      dotstorm: {
        slug: "my-dotstorm"
        name: "My Dotstorm"
        topic: "This is my topic"
      }
    }, (err, doc, event, si) ->
      _no_err_args([err, doc, event, si])

      expect(doc.slug).to.be("my-dotstorm")
      expect(doc.name).to.be("My Dotstorm")
      expect(doc.topic).to.be("This is my topic")
      expect(doc.url).to.be("/d/my-dotstorm/")
      expect(doc.absolute_url).to.be(config.apps.dotstorm.url + "/d/my-dotstorm/")

      expect(event.type).to.be("create")
      expect(event.application).to.be("dotstorm")
      expect(event.entity).to.be(doc.id)
      expect(event.url).to.be(doc.url)
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.data).to.eql({entity_name: 'My Dotstorm'})
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Dotstorm"
        aspect: "\"My Dotstorm\""
        collective: "created dotstorms"
        verbed: "created"
        manner: ""
      })

      expect(si.application).to.be("dotstorm")
      expect(si.entity).to.be(doc.id)
      expect(si.type).to.be("dotstorm")
      expect(si.url).to.be(doc.url)
      expect(si.absolute_url).to.be(doc.absolute_url)
      expect(si.title).to.be(doc.name)
      expect(si.summary).to.be("This is my topic (0 ideas)")
      expect(si.text).to.be("My Dotstorm\nThis is my topic")

      done()

  it "edits a dotstorm", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, doc) ->
      dslib.edit_dotstorm session, {
        dotstorm: {
          _id: doc._id
          name: "Muah Downstorm"
          topic: "Thees Ees Muah Downstorm"
        }
      }, (err, doc, event, si) ->
        _no_err_args([err, doc, event, si])

        expect(doc.slug).to.be("my-dotstorm")
        expect(doc.name).to.be("Muah Downstorm")
        expect(doc.topic).to.be("Thees Ees Muah Downstorm")
        expect(doc.url).to.be("/d/my-dotstorm/")
        expect(doc.absolute_url).to.be(config.apps.dotstorm.url + "/d/my-dotstorm/")

        expect(event.type).to.be("update")
        expect(event.application).to.be("dotstorm")
        expect(event.entity).to.be(doc.id)
        expect(event.url).to.be(doc.url)
        expect(event.absolute_url).to.be(doc.absolute_url)
        expect(event.data).to.eql({
          entity_name: 'Muah Downstorm'
          old_name: "My Dotstorm"
          old_topic: "This is my topic"
          name: "Muah Downstorm"
          topic: "Thees Ees Muah Downstorm"
        })

        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(2)
        expect(terms[0]).to.eql({
          entity: "Muah Downstorm"
          aspect: "name"
          collective: "changed dotstorms"
          verbed: "changed"
          manner: 'from "My Dotstorm" to "Muah Downstorm"'
        })
        expect(terms[1]).to.eql({
          entity: "Muah Downstorm"
          aspect: "topic"
          collective: "changed dotstorms"
          verbed: "changed"
          manner: 'from "This is my topic" to "Thees Ees Muah Downstorm"'
        })
        done()

  it "fetches a dotstorm", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, docy) ->
      _no_err_args([err, docy])
      dslib.get_dotstorm session, {dotstorm: {_id: docy._id}}, (err, doc, light_ideas, event) ->
        _no_err_args([err, doc, light_ideas, event])
        expect(doc.id).to.be(docy.id)

        expect(event.type).to.be("visit")
        expect(event.application).to.be("dotstorm")
        expect(event.entity).to.be(doc.id)
        expect(event.url).to.be(doc.url)
        expect(event.absolute_url).to.be(doc.absolute_url)
        expect(event.data).to.eql({entity_name: "Muah Downstorm"})
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Muah Downstorm"
          aspect: ""
          collective: "visits"
          verbed: "visited"
          manner: ""
        })
        done()

  it "creates an idea", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, doc) ->
      _no_err_args([err, doc])
      dslib.create_idea session, {
        dotstorm: {_id: doc._id}
        idea: {
          description: "first run"
          drawing: [['pencil', 0, 0, 640, 640]]
          background: '#ff9033'
        }
      }, (err, dotstorm, idea, event, si) ->
        _no_err_args([err, dotstorm, idea, event, si])
      
        expect(dotstorm.groups.length).to.be(1)
        expect(dotstorm.groups[0].ideas.length).to.be(1)
        expect(dotstorm.groups[0].ideas[0]).to.eql(idea._id)

        expect(idea.background).to.be('#ff9033')
        expect(idea.drawing.length).to.be(1)
        expect(idea.drawing[0]).to.eql(['pencil', 0, 0, 640, 640])
        expect(idea.description).to.be("first run")
        expect(fs.existsSync(idea.getDrawingPath('small'))).to.be(true)

        expect(event.type).to.be("append")
        expect(event.application).to.be("dotstorm")
        expect(event.entity).to.be(dotstorm.id)
        expect(event.url).to.be(dotstorm.url)
        expect(event.absolute_url).to.be(dotstorm.absolute_url)
        expect(event.data).to.eql({
          entity_name: "Muah Downstorm"
          is_new: true
          image: idea.drawingURLs.small
          description: idea.description
        })

        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Muah Downstorm"
          aspect: "a note"
          collective: "added notes"
          verbed: "added"
          manner: "first run"
          image: idea.drawingURLs.small
        })
        done()

  it "creates an idea with a photo", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, doc) ->
      _no_err_args([err, doc])
      dslib.create_idea session, {
        dotstorm: {_id: doc._id}
        idea: {
          photoData: '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAYEBAQFBAYFBQYJBgUGCQsIBgYICwwKCgsKCgwQDAwMDAwMEAwODxAPDgwTExQUExMcGxsbHCAgICAgICAgICD/2wBDAQcHBw0MDRgQEBgaFREVGiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICD/wAARCAFKABsDAREAAhEBAxEB/8QAGQABAQEBAQEAAAAAAAAAAAAAAAECBAMI/8QAFxABAQEBAAAAAAAAAAAAAAAAABESE//EABQBAQAAAAAAAAAAAAAAAAAAAAD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwD6pAAAAAAABAAAASgUCgUEAAABAAAASgUCgUAAAAGQAAAKBQKBQQAAAEAAABAAAASgUCgUEAAABAAAASgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFAAAABkAAACgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFBAAAAQAAAEAAAB47A2BsDYOboB0A6AdAc3QDoB0A6A5tgbA2BsGQAAAf/Z'
        }
      }, (err, dotstorm, idea, event, si) ->
        _no_err_args([err, dotstorm, idea, event, si])

        expect(dotstorm.groups.length).to.be(2)
        expect(dotstorm.groups[0].ideas[0]).to.eql(idea._id)

        expect(fs.existsSync(idea.getPhotoPath('small'))).to.be(true)
        expect(idea.photoVersion > 0).to.be(true)
        expect(idea.photoData).to.be(undefined)

        expect(event.type).to.be("append")
        expect(event.application).to.be("dotstorm")
        expect(event.entity).to.be(dotstorm.id)
        expect(event.url).to.be(dotstorm.url)
        expect(event.absolute_url).to.be(dotstorm.absolute_url)
        expect(event.data).to.eql({
          entity_name: "Muah Downstorm"
          is_new: true
          image: idea.drawingURLs.small
          description: idea.description
        })

        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Muah Downstorm"
          aspect: "a note"
          collective: "added notes"
          verbed: "added"
          manner: ""
          image: idea.drawingURLs.small
        })
        done()

  it "edits an idea", (done) ->
    ds_schema.Idea.findOne {description: "first run"}, (err, idea) ->
      _no_err_args([err, idea])

      dslib.edit_idea session, {
        idea: {_id: idea._id, description: "muy calliente"}
      }, (err, dotstorm, idea, event, si) ->
        _no_err_args([err, dotstorm, idea, event, si])

        expect(dotstorm.groups.length).to.be(2)
        expect(dotstorm.groups[1].ideas[0]).to.eql(idea._id)

        expect(idea.description).to.be("muy calliente")
        expect(idea.background).to.be("#ff9033")

        expect(event.type).to.be("append")
        expect(event.application).to.be("dotstorm")
        expect(event.entity).to.be(dotstorm.id)
        expect(event.url).to.be(dotstorm.url)
        expect(event.absolute_url).to.be(dotstorm.absolute_url)
        expect(event.data).to.eql({
          entity_name: "Muah Downstorm"
          is_new: false
          image: idea.drawingURLs.small
          description: "muy calliente"
        })
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Muah Downstorm"
          aspect: "a note"
          collective: "edited notes"
          verbed: "edited"
          manner: ""
          image: idea.drawingURLs.small
        })

        expect(si.summary).to.be("Thees Ees Muah Downstorm (2 ideas)")
        expect(si.text).to.be(
          "Muah Downstorm\nThees Ees Muah Downstorm\nmuy calliente"
        )
        done()
    
  it "fetches an idea", (done) ->
    ds_schema.Idea.findOne {description: "muy calliente"}, (err, doc) ->
      _no_err_args([err, doc])
      dslib.get_idea session, {idea: {_id: doc._id}}, (err, dotstorm, idea) ->
        expect(idea.drawing.length).to.be(1)
        expect(idea.drawing[0]).to.eql(['pencil', 0, 0, 640, 640])
        done()

  it "rearranges ideas", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, orig_doc) ->
      _no_err_args([err, orig_doc])
      # Try moving something to the trash.
      dslib.rearrange session, {
        dotstorm: {_id: orig_doc._id, groups: orig_doc.groups, trash: orig_doc.trash}
        movement: [1, 0, null, null, 0]
      }, (err, doc, si) ->
        _no_err_args([err, doc, si])

        expect(doc.trash.length).to.be(1)
        expect(doc.trash[0]).to.eql(orig_doc.groups[1].ideas[0])

        expect(si.summary).to.be("Thees Ees Muah Downstorm (1 idea)")
        expect(si.text).to.be("Muah Downstorm\nThees Ees Muah Downstorm")

        # Now try re-calling a movement with the original doc -- should fail.
        dslib.rearrange session, {
          dotstorm: {_id: orig_doc._id, groups: orig_doc.groups, trash: orig_doc.trash}
          movement: [0, 0, null, null, 0]
        }, (err, doc, si) ->
          expect(err).to.be("Not found")
          expect(doc).to.be(undefined)
          expect(si).to.be(undefined)

          done()

  it "trashes a Dotstorm", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, doc) ->
      doc.sharing.group_id = _.find(session.groups, (g) -> g.slug == "three-members").id
      doc.save (err, doc) ->
        api_methods.trash_entity session, {
          application: "dotstorm"
          entity: doc.id
          group: doc.sharing.group_id
          trash: true
        }, (err, event, si, dotstorm) ->
          _no_err_args([err, event, si, dotstorm])
          expect(si.trash).to.be(true)
          expect(typeof dotstorm.trash).to.be("object")
          expect(dotstorm.archived).to.be(true)
          expect(event.type).to.be("trash")
          expect(event.absolute_url).to.be(dotstorm.absolute_url)
          expect(event.url).to.be(dotstorm.url)
          expect(event.entity).to.be(dotstorm.id)
          expect(event.application).to.be("dotstorm")
          terms = api_methods.get_event_grammar(event)
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: dotstorm.name
            aspect: "dotstorm"
            collective: "moved to trash"
            verbed: "moved to trash"
            manner: ""
          })
          done()

  it "untrashes a Dotstorm", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, doc) ->
      api_methods.trash_entity session, {
        application: "dotstorm"
        entity: doc.id
        group: doc.sharing.group_id
        trash: false
      }, (err, event, si, dotstorm) ->
        _no_err_args([err, event, si, dotstorm])
        expect(si.trash).to.be(false)
        expect(typeof dotstorm.trash).to.be("object")
        expect(dotstorm.archived).to.be(false)
        expect(event.type).to.be("untrash")
        expect(event.absolute_url).to.be(dotstorm.absolute_url)
        expect(event.url).to.be(dotstorm.url)
        expect(event.entity).to.be(dotstorm.id)
        expect(event.application).to.be("dotstorm")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: dotstorm.name
          aspect: "dotstorm"
          collective: "restored from trash"
          verbed: "restored from trash"
          manner: ""
        })
        done()

  it "requests deletion", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, dotstorm) ->
      # Add an idea as a second user, so that we require confirmation to delete.
      dslib.create_idea session2, {
        dotstorm: {_id: dotstorm._id}
        idea: {
          description: "first run"
          drawing: [['pencil', 0, 0, 640, 640]]
          background: '#ff9033'
        }
      }, (err, dotstorm, idea, event, si) ->
        _no_err_args([err, dotstorm, idea, event, si])

        # Ensure we have multiple events
        www_schema.Event.find {entity: dotstorm._id}, (err, events) ->
          users = _.unique(_.map(events, (e) -> e.user.toString()))
          expect(users.length > 1).to.be(true)

          # Request deletion
          api_methods.request_deletion session, {
            application: "dotstorm"
            entity: dotstorm.id
            group: dotstorm.sharing.group_id
            url: dotstorm.url
            title: dotstorm.title
          }, (err, dr, trashing, event, notices) ->
            _no_err_args([err, dr, trashing, event, notices])
            [trash_event, si, dotstorm] = trashing
            _no_err_args([null, trash_event, si, dotstorm])

            expect(dotstorm.archived).to.be(true)
            expect(si.trash).to.be(true)

            expect(event.type).to.be("deletion")
            expect(event.url).to.be(dr.entity_url)
            expect(event.absolute_url).to.be(dotstorm.absolute_url)
            expect(event.entity).to.be(dotstorm.id)
            expect(event.application).to.be('dotstorm')
            terms = api_methods.get_event_grammar(event)
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: dotstorm.title
              aspect: "dotstorm"
              collective: "requests to delete"
              verbed: "requested deletion"
              manner: "by #{event.data.end_date.toString()}"
            })
            done()

  it "confirms deletion", (done) ->
    ds_schema.Dotstorm.findOne {}, (err, dotstorm) ->
      ds_schema.Idea.find {}, (err, ideas) ->
        expect(ideas.length > 1).to.be(true)
        www_schema.DeletionRequest.findOne {entity: dotstorm.id}, (err, dr) ->
          api_methods.confirm_deletion session2, dr._id, (err, notices) ->
            expect(err).to.be(null)
            expect(notices).to.be(undefined)
            ds_schema.Dotstorm.findOne {_id: dotstorm._id}, (err, doc) ->
              expect(err).to.be(null)
              expect(doc).to.be(null)
              async.map ideas, (idea, done) ->
                expect(fs.existsSync(idea.getDrawingPath('small'))).to.be(false)
                ds_schema.Idea.findOne {_id: idea._id}, (err, doc) ->
                  expect(err).to.be(null)
                  expect(doc).to.be(null)
                  done()
              , done
