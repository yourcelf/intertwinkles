expect     = require 'expect.js'
_          = require 'underscore'
Browser    = require 'zombie'
mongoose   = require 'mongoose'
fs         = require 'fs'
h          = require './helper'
models     = require '../lib/schema'

#
# Test CRUD for ideas and dotstorms for the whole socket pipeline.
#
describe "socket pipeline", ->
  before (done) ->
    mongoose.disconnect =>
      @server = h.startServer()
      @browser  = new Browser()
      @browser2 = new Browser()
      h.clearDb(done)

  after (done) ->
    @server.app.close()
    h.clearDb(-> mongoose.disconnect(done))

  it "visits the front page", (done) ->
    @browser.visit "http://localhost:8127", =>
      expect(@browser.text("title")).to.be "DotStorm"
      h.waitsFor =>
        socketid = @browser.evaluate("ds.socket.socket.sessionid")
        if socketid?
          expect(@server.io.roomClients[socketid]).to.not.be undefined
          done()
          return true
  
  it "connects to a room", (done) ->
    @browser.fill("#id_join", "test").pressButton "OK", =>
      h.waitsFor =>
        if @browser.evaluate("window.location.pathname") == "/d/test/"
          done()
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
    h.waitsFor =>
      backboneIdea = @browser.evaluate("window.testIdea")
      if backboneIdea != undefined
        models.Idea.findOne {_id: backboneIdea.id}, (err, doc) =>
          @idea = doc
          expect("" + doc.dotstorm_id).to.eql @dotstorm_id
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(doc.background).to.be '#ff9033'
          done()
        return true

  it "updates an idea", (done) ->
    @browser.evaluate("window.testIdea.save({
      description: 'updated'
    }, {
      success: function(model) {
        window.ideaUpdateSuccess = true;
      }
    });")
    h.waitsFor =>
      if @browser.evaluate("window.ideaUpdateSuccess")
        startingVersion = @idea.imageVersion
        models.Idea.findOne {_id: @idea._id}, (err, doc) =>
          @idea = doc
          expect(doc.description).to.be 'updated'
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(parseInt(@idea.imageVersion) > startingVersion).to.be true
          done()
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
    h.waitsFor =>
      model = @browser.evaluate("window.ideaWithPhoto")
      if model?
        models.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(fs.existsSync doc.getPhotoPath('small')).to.be true
          expect(doc.photoVersion > 0).to.be true
          expect(doc.photoData).to.be undefined
          done()
        return true
      
  it "saves tags", (done) ->
    @browser.evaluate("new ds.Idea({_id: '#{@idea._id}'}).fetch({
        success: function(model) {
          model.save({'tags': ['one', 'two', 'three']}, {
            success: function(model) {
              window.taggedModel = model;
            }
          });
        }
      });
    ")
    h.waitsFor =>
      model = @browser.evaluate("window.taggedModel")
      if model?
        expect(model.get("tags")).to.eql ["one", "two", "three"]
        models.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(_.isEqual doc.tags, ["one", "two", "three"]).to.be true
        done()
        return true

  it "reads an idea", (done) ->
    @browser.evaluate("new ds.Idea({
      _id: '#{@idea._id}'
    }).fetch({
      success: function(model) {
        window.ideaReadSuccess = true;
      }
    });")
    h.waitsFor =>
      if @browser.evaluate("window.ideaReadSuccess")
        done()
        return true

  it "reads a non-existent idea", (done) ->
    @browser.evaluate("new ds.Idea({_id: 'no exist'}).fetch({
      success: function(model) {
        window.ideaReadNoExist = model.toJSON();
      }
    });")
    h.waitsFor =>
      nonexistent = @browser.evaluate("window.ideaReadNoExist")
      if nonexistent?
        expect(nonexistent).to.eql {_id: 'no exist'}
        done()
        return true

  it "reads an idea from a collection", (done) ->
    @browser.evaluate("new ds.IdeaList().fetch({
      query: {dotstorm_id: '#{@dotstorm_id}'},
      success: function(coll) {
        window.ideaReadColl = coll;
      }
    });")
    h.waitsFor =>
      coll = @browser.evaluate("window.ideaReadColl")
      if coll?
        expect(coll.models[0].attributes.drawing).to.be undefined
        done()
        return true

  it "reads an empty collection", (done) ->
    @browser.evaluate("new ds.IdeaList().fetch({
      query: {dotstorm_id: 'fiddlesticks'},
      success: function(coll) {
        window.ideaReadEmptyColl = coll;
      }, 
      error: function(err) { console.log(err); }
    });")
    h.waitsFor =>
      emptyColl = @browser.evaluate("window.ideaReadEmptyColl")
      if emptyColl?
        expect(emptyColl.length).to.be 0
        done()
        return true

  it "deletes an idea", (done) ->
    @browser.evaluate("window.testIdea.destroy({
      success: function() {
        window.ideaDeleteSuccess = true;
      }
    });")
    h.waitsFor =>
      if @browser.evaluate("window.ideaDeleteSuccess")
        models.Idea.findOne {_id: @idea._id}, (err, doc) =>
          expect(doc).to.be null
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be false
          done()
        return true
    
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
    h.waitsFor =>
      dotstorm = @browser.evaluate("window.createdDotstorm")
      if dotstorm?
        expect(dotstorm.get "slug").to.be 'crazyslug'
        done()
        return true

  it "reads a dotstorm coll", (done) ->
    @browser.evaluate("
      window.dotstormColl = null;
      new ds.DotstormList().fetch({
        success: function(coll) {
          window.dotstormColl = coll;
        }
      });")
    h.waitsFor =>
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
    h.waitsFor =>
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
    h.waitsFor =>
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
    h.waitsFor =>
      dotstorm = @browser.evaluate("window.readDotstorm")
      if dotstorm?
        expect(dotstorm.id).to.be @dotstorm_id
        done()
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
    h.waitsFor =>
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
    h.waitsFor =>
      if @browser.evaluate("window.dotstormUpdated")
        models.Dotstorm.findOne {slug: 'test'}, (err, doc) =>
          expect(doc.name).to.be 'new name'
          done()
        return true

  it "deletes a dotstorm", (done) ->
    @browser.evaluate("
      ds.model.destroy({
        success: function() {
          window.dotstormDestroyed = true;
        }
      });")
    h.waitsFor =>
      if @browser.evaluate("window.dotstormDestroyed")
        models.Dotstorm.findOne {slug: 'test'}, (err, doc) =>
          expect(doc).to.be null
          done()
        return true
