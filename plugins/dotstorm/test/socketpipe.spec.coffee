expect     = require 'expect.js'
async      = require 'async'
_          = require 'underscore'
Browser    = require 'zombie'
mongoose   = require 'mongoose'
fs         = require 'fs'

common     = require '../../../test/common'
config     = require '../../../test/test_config'

schema      = require('../lib/schema').load(config)
www_schema  = require('../../../lib/schema').load(config)
api_methods = require('../../../lib/api_methods')(config)

#
# Test CRUD for ideas and dotstorms for the whole socket pipeline.
#

await = (fn) ->
  if fn() == true
    return
  setTimeout (-> await fn), 100

describe "Dotstorm socket pipeline", ->
  this.timeout(20000)
  before (done) ->
    common.startUp (server) =>
      @server = server
      @browser = common.fetchBrowser()
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "visits the front page", (done) ->
    @browser.visit config.apps.dotstorm.url + "/", (blank, browser, status, errors) =>
      await =>
        if @browser.querySelector(".new-dotstorm")?
          @browser.clickLink("New dotstorm")
          await =>
            if @browser.querySelector("#add")?
              done()
              return true
          return true
  
  it "connects to a room", (done) ->
    @browser.fill("#id_slug", "test").pressButton "Create dotstorm", =>
      await =>
        if @browser.evaluate("window.location.pathname") == "/dotstorm/d/test/"
          schema.Dotstorm.findOne {slug: "test"}, (err, doc) ->
            expect(err).to.be(null)
            expect(doc).to.not.be(null)
            expect(doc.slug).to.be("test")
            www_schema.Event.find {entity: doc._id}, (err, events) ->
              expect(events.length).to.be(1)
              expect(events[0].type).to.be("create")
              terms = api_methods.get_event_grammar(events[0])
              expect(terms.length).to.be(1)
              expect(terms[0]).to.eql({
                entity: "Dotstorm"
                aspect: "\"Untitled\""
                collective: "created dotstorms"
                verbed: "created"
                manner: ""
              })
              # Clear events for de-comlecting of tests
              async.map(events, ((e, done) -> e.remove(done)), done)
          return true

  it "creates an idea", (done) ->
    @dotstorm_id = @browser.evaluate("ds.model.id")
    expect(@dotstorm_id).to.not.be undefined
    @browser.evaluate("new ds.Idea({
      dotstorm_id: '#{@dotstorm_id}',
      description: 'first run',
      drawing: [['pencil', 0, 0, 640, 640]],
      background: '#ff9033'
    }).save({}, {
      success:  function(model) {
        window.testIdea = model;
      }
    });")
    await =>
      backboneIdea = @browser.evaluate("window.testIdea")
      if backboneIdea != undefined
        schema.Idea.findOne {_id: backboneIdea.id}, (err, doc) =>
          @idea = doc
          expect("" + doc.dotstorm_id).to.eql @dotstorm_id
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(doc.background).to.be '#ff9033'
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "idea"
              collective: "added ideas"
              verbed: "added"
              manner: "first run"
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "updates an idea", (done) ->
    @browser.evaluate("window.testIdea.save({
      description: 'updated'
    }, {
      success: function(model) {
        window.ideaUpdateSuccess = true;
      }
    });")
    await =>
      if @browser.evaluate("window.ideaUpdateSuccess")
        startingVersion = @idea.imageVersion
        schema.Idea.findOne {_id: @idea._id}, (err, doc) =>
          @idea = doc
          expect(doc.description).to.be 'updated'
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(parseInt(@idea.imageVersion) > startingVersion).to.be true
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "idea"
              collective: "edited ideas"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "uploads a photo", (done) ->
    @browser.evaluate("new ds.Idea({
          _id: '#{@idea._id}',
          photoData: '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAYEBAQFBAYFBQYJBgUGCQsIBgYICwwKCgsKCgwQDAwMDAwMEAwODxAPDgwTExQUExMcGxsbHCAgICAgICAgICD/2wBDAQcHBw0MDRgQEBgaFREVGiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICD/wAARCAFKABsDAREAAhEBAxEB/8QAGQABAQEBAQEAAAAAAAAAAAAAAAECBAMI/8QAFxABAQEBAAAAAAAAAAAAAAAAABESE//EABQBAQAAAAAAAAAAAAAAAAAAAAD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwD6pAAAAAAABAAAASgUCgUEAAABAAAASgUCgUAAAAGQAAAKBQKBQQAAAEAAABAAAASgUCgUEAAABAAAASgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFAAAABkAAACgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFBAAAAQAAAEAAAB47A2BsDYOboB0A6AdAc3QDoB0A6A5tgbA2BsGQAAAf/Z'
        }).save(null, {
          success: function(model) {
            window.ideaWithPhoto = model;   
          }
        });
      ")
    await =>
      model = @browser.evaluate("window.ideaWithPhoto")
      if model?
        schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(fs.existsSync doc.getPhotoPath('small')).to.be true
          expect(doc.photoVersion > 0).to.be true
          expect(doc.photoData).to.be undefined
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "idea"
              collective: "edited ideas"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true
      
  it "saves tags", (done) ->
    @browser.evaluate("new ds.Idea({_id: '#{@idea.id}', dotstorm_id: '#{@idea.dotstorm_id}'}).fetch({
        success: function(model) {
          model.save({'tags': ['one', 'two', 'three']}, {
            success: function(model) {
              window.taggedModel = model;
            }
          });
        }
      });
    ")
    await =>
      model = @browser.evaluate("window.taggedModel")
      if model?
        expect(model.get("tags")).to.eql ["one", "two", "three"]
        schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(_.isEqual doc.tags, ["one", "two", "three"]).to.be true
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "idea"
              collective: "edited ideas"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "reads an idea", (done) ->
    @browser.evaluate("new ds.Idea({
      _id: '#{@idea._id}', dotstorm_id: '#{@idea.dotstorm_id}'
    }).fetch({
      success: function(model) {
        window.ideaReadSuccess = true;
      }
    });")
    await =>
      if @browser.evaluate("window.ideaReadSuccess")
        done()
        return true

  it "reads a non-existent idea", (done) ->
    # Use the dotstorm_id as a stand-in for a non-existent idea._id
    @browser.evaluate("new ds.Idea({
        _id: '#{@idea.dotstorm_id}',
        dotstorm_id: '#{@idea.dotstorm_id}'
      }).fetch({
        error: function(model) {
          window.ideaReadNoExist = true
        }
      });")
    await =>
      nonexistent = @browser.evaluate("window.ideaReadNoExist")
      if nonexistent?
        done()
        return true

  it "reads an idea from a collection", (done) ->
    @browser.evaluate("new ds.IdeaList().fetch({
      query: {dotstorm_id: '#{@dotstorm_id}'},
      success: function(coll) {
        window.ideaReadColl = coll;
      }
    });")
    await =>
      coll = @browser.evaluate("window.ideaReadColl")
      if coll?
        expect(coll.models[0].attributes.drawing).to.be undefined
        done()
        return true

  it "reads an non-existent collection", (done) ->
    # Use the idea_id as a stand-in for a non-existent dotstorm_id
    @browser.evaluate("new ds.IdeaList().fetch({
      query: {dotstorm_id: '#{@idea.id}'},
      error: function(err) { 
        window.ideaReadNonExistentColl = true
      }
    });")
    await =>
      emptyColl = @browser.evaluate("window.ideaReadNonExistentColl")
      if emptyColl == true
        done()
        return true

# Delete method removed.
#  it "deletes an idea", (done) ->
#    @browser.evaluate("window.testIdea.destroy({
#      success: function() {
#        window.ideaDeleteSuccess = true;
#      }
#    });")
#    await =>
#      if @browser.evaluate("window.ideaDeleteSuccess")
#        schema.Idea.findOne {_id: @idea._id}, (err, doc) =>
#          expect(doc).to.be null
#          expect(fs.existsSync @idea.getDrawingPath('small')).to.be false
#          done()
#        return true
    
  it "creates a dotstorm", (done) ->
    @browser.evaluate("new ds.Dotstorm({
      slug: 'crazyslug'
    }).save({}, {
      success: function(model) {
        window.createdDotstorm = model;
      },
      error: function(model, err) {
        console.log(err.error);
      }
    });")
    await =>
      dotstorm = @browser.evaluate("window.createdDotstorm")
      if dotstorm?
        expect(dotstorm.get "slug").to.be 'crazyslug'
        www_schema.Event.find {entity: dotstorm.id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("create")
          expect(events[0].data.entity_name).to.be("Untitled")
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "reads a dotstorm coll", (done) ->
    @browser.evaluate("
      window.dotstormColl = null;
      new ds.DotstormList().fetch({
        success: function(coll) {
          window.dotstormColl = coll;
        }
      });")
    await =>
      coll = @browser.evaluate("window.dotstormColl")
      if coll?
        expect(coll.length).to.be 2
        done()
        return true

  it "reads a constrained dotstorm coll", (done) ->
    @browser.evaluate("
        window.dotstormColl = null;
        new ds.DotstormList().fetch({
          query: { slug: 'crazyslug' },
          success: function(coll) {
            window.dotstormColl = coll;
          }
        });")
    await =>
      coll = @browser.evaluate("window.dotstormColl")
      if coll?
        expect(coll.length).to.be 1
        expect(coll.models[0].get("slug")).to.be "crazyslug"
        done()
        return true


  it "reads an empty dotstorm", (done) ->
    @browser.evaluate("
      window.dotstormColl = null;
      new ds.DotstormList().fetch({
        query: { slug: 'nonexistent' },
        success: function(coll) {
          window.dotstormColl = coll;
        }
      });")
    await =>
      coll = @browser.evaluate("window.dotstormColl")
      if coll?
        expect(coll.length).to.be 0
        done()
        return true

  it "reads a single dotstorm", (done) ->
    @browser.evaluate("
      window.readDotstorm = null;
      new ds.Dotstorm({
          slug: 'test'
        }).fetch({
        success: function(model) {
          window.readDotstorm = model;
        }
      });")
    await =>
      dotstorm = @browser.evaluate("window.readDotstorm")
      if dotstorm?
        expect(dotstorm.id).to.be @dotstorm_id
        www_schema.Event.find {entity: dotstorm.id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("visit")
          terms = api_methods.get_event_grammar(events[0])
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: "Untitled"
            aspect: "dotstorm"
            collective: "visited dotstorms"
            verbed: "visited"
            manner: ''
          })
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "reads a single empty dotstorm", (done) ->
    @browser.evaluate("
      window.readDotstorm = null;
      new ds.Dotstorm({
          slug: 'nonexistent'
        }).fetch({
        success: function(model) {
          window.readDotstorm = model;
        }
      });")
    await =>
      dotstorm = @browser.evaluate("window.readDotstorm")
      if dotstorm?
        expect(dotstorm.id).to.be undefined
        done()
        return true

  it "updates a dotstorm", (done) ->
    @browser.evaluate("
      ds.model.save({
        name: 'new name'
      }, {
        success: function(model) {
          window.dotstormUpdated = true;
        }
      });")
    await =>
      if @browser.evaluate("window.dotstormUpdated")
        schema.Dotstorm.findOne {slug: 'test'}, (err, doc) =>
          expect(doc.name).to.be 'new name'
          www_schema.Event.find {entity: doc._id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("update")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "new name"
              aspect: "name"
              collective: "changed dotstorms"
              verbed: "changed"
              manner: 'from "" to "new name"'
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)

        return true

# Delete method removed.
#  it "deletes a dotstorm", (done) ->
#    @browser.evaluate("
#      ds.model.destroy({
#        success: function() {
#          window.dotstormDestroyed = true;
#        }
#      });")
#    await =>
#      if @browser.evaluate("window.dotstormDestroyed")
#        schema.Dotstorm.findOne {slug: 'test'}, (err, doc) =>
#          expect(doc).to.be null
#          done()
#        return true
