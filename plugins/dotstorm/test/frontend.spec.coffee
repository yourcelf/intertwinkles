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
log4js = require("log4js")
log4js.getLogger("socket_server").setLevel(log4js.levels.FATAL)

#
# Test CRUD for ideas and dotstorms for the whole socket pipeline.
#

await = (fn) ->
  if fn() == true
    return
  setTimeout (-> await fn), 100

describe "Dotstorm frontend", ->
  this.timeout(20000)
  server = null
  browser = null

  before (done) ->
    common.startUp (theServer) ->
      server = theServer
      common.fetchBrowser (theBrowser) ->
        browser = theBrowser
        done()

  after (done) ->
    browser.quit().then -> common.shutDown(server, done)

  it "visits the front page", (done) ->
    browser.get(config.apps.dotstorm.url + "/")
    browser.wait ->
      browser.getCurrentUrl().then (url) ->
        return url == config.apps.dotstorm.url + "/"
    browser.byCss(".new-dotstorm").click()
    browser.wait ->
      browser.byCsss("#add").then (els) ->
        return els.length > 0
    .then -> done()
  
  it "connects to a room", (done) ->
    browser.byCss("#id_slug").sendKeys("test")
    browser.byCss(".btn-primary").click()
    browser.wait ->
      browser.executeScript("return window.location.pathname").then (url) ->
        return url == "/dotstorm/d/test/"
    .then ->
      schema.Dotstorm.findOne {slug: "test"}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(doc.url).to.be("/d/test/")
        expect(doc.absolute_url).to.be(config.apps.dotstorm.url + "/d/test/")
        expect(doc.slug).to.be("test")
        www_schema.Event.find {entity: doc._id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("create")
          expect(events[0].url).to.be(doc.url)
          expect(events[0].absolute_url).to.be(doc.absolute_url)
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

  it "creates an idea", (done) ->
    @dotstorm_id = null
    browser.executeScript("return ds.app.dotstorm.id;").then (res) =>
      expect(res?).to.not.be(false)
      @dotstorm_id = res
    .then =>
      browser.executeScript("intertwinkles.socket.send('dotstorm/create_idea', {
        dotstorm: { _id: '#{@dotstorm_id}' },
        idea: {
          description: 'first run',
          drawing: [['pencil', 0, 0, 640, 640]],
          background: '#ff9033'
        }
      });
      ds.app.ideas.once('add', function(idea) { window.testIdea = idea; });")
    .then =>
      idea_id = null
      browser.wait ->
        browser.executeScript("return window.testIdea && window.testIdea.id;").then (res) ->
          idea_id = res
          return res?
      .then =>
        schema.Idea.findOne {_id: idea_id}, (err, doc) =>
          @idea = doc
          expect("" + doc.dotstorm_id).to.eql @dotstorm_id
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(doc.background).to.be '#ff9033'
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            expect(events[0].url).to.be("/d/test/")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "a note"
              collective: "added notes"
              verbed: "added"
              manner: "first run"
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, cb) -> e.remove(cb)), done)
        return true

  it "updates an idea", (done) ->
    browser.executeScript("intertwinkles.socket.send('dotstorm/edit_idea', {
        idea: {_id: testIdea.id, description: 'updated'}
      });
      testIdea.once('change', function() {
        window.ideaUpdateSuccess = true;
      });
    ")
    browser.wait ->
      browser.executeScript("return window.ideaUpdateSuccess;").then (res) ->
        return res == true
    .then =>
      startingVersion = @idea.imageVersion
      schema.Idea.findOne {_id: @idea._id}, (err, doc) =>
        @idea = doc
        expect(doc.description).to.be 'updated'
        expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
        expect(parseInt(@idea.imageVersion) > startingVersion).to.be true
        www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("append")
          expect(events[0].url).to.be("/d/test/")
          terms = api_methods.get_event_grammar(events[0])
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: "Untitled"
            aspect: "a note"
            collective: "edited notes"
            verbed: "edited"
            manner: ""
            image: doc.drawingURLs.small
          })
          # Clear events for de-comlecting of tests
          async.map(events, ((e, cb) -> e.remove(cb)), done)

  it "uploads a photo", (done) ->
    browser.executeScript("intertwinkles.socket.send('dotstorm/edit_idea', {idea: {
          _id: '#{@idea._id}',
          photoData: '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAYEBAQFBAYFBQYJBgUGCQsIBgYICwwKCgsKCgwQDAwMDAwMEAwODxAPDgwTExQUExMcGxsbHCAgICAgICAgICD/2wBDAQcHBw0MDRgQEBgaFREVGiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICD/wAARCAFKABsDAREAAhEBAxEB/8QAGQABAQEBAQEAAAAAAAAAAAAAAAECBAMI/8QAFxABAQEBAAAAAAAAAAAAAAAAABESE//EABQBAQAAAAAAAAAAAAAAAAAAAAD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwD6pAAAAAAABAAAASgUCgUEAAABAAAASgUCgUAAAAGQAAAKBQKBQQAAAEAAABAAAASgUCgUEAAABAAAASgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFAAAABkAAACgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFBAAAAQAAAEAAAB47A2BsDYOboB0A6AdAc3QDoB0A6A5tgbA2BsGQAAAf/Z'
        }});
        ds.app.ideas.get('#{@idea._id}').once('change', function(idea) {
          window.ideaWithPhoto = idea;
        });
      ")
    browser.wait ->
      browser.executeScript("return window.ideaWithPhoto && window.ideaWithPhoto.id;").then (res) ->
        return res?
    .then =>
      schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
        expect(fs.existsSync doc.getPhotoPath('small')).to.be true
        expect(doc.photoVersion > 0).to.be true
        expect(doc.photoData).to.be undefined
        www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("append")
          expect(events[0].url).to.be("/d/test/")
          terms = api_methods.get_event_grammar(events[0])
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: "Untitled"
            aspect: "a note"
            collective: "edited notes"
            verbed: "edited"
            manner: ""
            image: doc.drawingURLs.small
          })
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)
      return true
      
  it "saves tags", (done) ->
    browser.executeScript("
      intertwinkles.socket.send('dotstorm/edit_idea', {
        idea: {_id: '#{@idea.id}', tags: ['one', 'two', 'three']}
      });
      ds.app.ideas.get('#{@idea.id}').once('change', function(model) {
        window.taggedModel = model;
      });
    ")
    tags = null
    browser.wait ->
      browser.executeScript(
        "return window.taggedModel && window.taggedModel.get('tags')"
      ).then (res) ->
        tags = res
        return res?
    .then =>
      expect(tags).to.eql ["one", "two", "three"]
      schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
        expect(_.isEqual doc.tags, ["one", "two", "three"]).to.be true
        www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("append")
          expect(events[0].url).to.be("/d/test/")
          terms = api_methods.get_event_grammar(events[0])
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: "Untitled"
            aspect: "a note"
            collective: "edited notes"
            verbed: "edited"
            manner: ""
            image: doc.drawingURLs.small
          })
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)

  it "reads an idea", (done) ->
    browser.executeScript("
      intertwinkles.socket.send('dotstorm/get_idea', {
        idea: {_id: '#{@idea._id}'}
      });
      ds.app.ideas.on('load', function() {
        window.ideaReadSuccess = true;
      });")
    browser.wait ->
      browser.executeScript("return window.ideaReadSuccess").then (res) ->
        return res == true
    .then -> done()

  it "reads a non-existent idea", (done) ->
    # Use the dotstorm_id as a stand-in for a valid objectID which non-existent
    # doesn't exist as an idea._id
    browser.executeScript("
      intertwinkles.socket.send('dotstorm/get_idea', {
        idea: {_id: '#{@idea.dotstorm_id}'}
      });
      intertwinkles.socket.once('error', function() {
        window.ideaReadNoExist = true;
      });")
    browser.wait ->
      browser.executeScript("return window.ideaReadNoExist").then (res) ->
        return res == true
    .then -> done()

  it "creates a dotstorm", (done) ->
    browser.executeScript("
      intertwinkles.socket.send('dotstorm/create_dotstorm', {
        dotstorm: {slug: 'crazyslug'}
      });
      ds.app.dotstorm.on('load', function(model) {
        window.createdDotstorm = model;
      });
    ")
    slug = null
    browser.wait ->
      browser.executeScript(
        "return window.createdDotstorm && window.createdDotstorm.get('slug')"
      ).then (res) ->
        slug = res
        return res?
    .then ->
      expect(slug).to.be 'crazyslug'
      schema.Dotstorm.findOne {slug: slug}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        www_schema.Event.find {entity: doc._id}, (err, events) ->
          expect(events[0].type).to.be("create")
          expect(events[0].data.entity_name).to.be("Untitled")
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)
