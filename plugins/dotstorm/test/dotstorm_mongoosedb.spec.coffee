expect   = require 'expect.js'
mongoose = require 'mongoose'
fs       = require 'fs'
_        = require 'underscore'
config   = require '../../../test/test_config'
models   = require('../lib/schema').load(config)
common   = require '../../../test/common'

describe "Dotstorm Mongoose connector", ->
  before (done) ->
    common.startUp (server, browser) =>
      @server = server
      @browser = browser
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "creates a dotstorm", (done) ->
    new models.Dotstorm({
      slug: "test"
    }).save (err) ->
      expect(err).to.be null
      models.Dotstorm.findOne {slug: "test"}, (err, doc) ->
        expect(err).to.be null
        expect(doc.slug).to.eql "test"
        done()

  it "creates an idea", (done) ->
    models.Dotstorm.findOne {slug: "test"}, (err, dotstorm) =>
      @dotstorm = dotstorm
      idea = new models.Idea({
        dotstorm_id: dotstorm._id
        description: "open to creative possibility"
        background: "#ffffdd"
      })
      idea.save (err) ->
        expect(err).to.be null
        dotstorm.groups.push new models.IdeaGroup(ideas: [idea._id])
        dotstorm.save (err) ->
          expect(err).to.be(null)
          models.Idea.findOne {}, (err, idea) ->
            expect(err).to.be null
            expect(idea.description).to.be "open to creative possibility"
            done()

  it "creates a drawing", (done) ->
    models.Idea.findOne {dotstorm_id: @dotstorm._id}, (err, idea) =>
      expect(err).to.be null
      idea.drawing = [["pencil", 0, 0, 64, 64]]
      idea.background = "#ffffff"
      idea.save (err) ->
        expect(err).to.be null
        expect(idea.drawingURLs.small).to.be "/uploads/dotstorm/idea/#{idea._id}/drawing/small#{idea.imageVersion}.png"
        expect(fs.existsSync idea.getDrawingPath("small")).to.be true
        done()

  it "returns light ideas", (done) ->
    models.Idea.findOneLight {dotstorm_id: @dotstorm._id}, (err, idea) =>
      expect(err).to.be null
      expect(idea.drawing).to.be undefined
      done()
 
  it "populates ideas in dotstorm", (done) ->
    models.Dotstorm.withLightIdeas {}, (err, dotstorm) ->
      expect(err).to.be null
      idea = dotstorm.groups[0].ideas[0]
      expect(idea.description).to.be "open to creative possibility"
      expect(idea.drawing).to.be undefined
      done()

  it "saves tags", (done) ->
    models.Idea.findOne {dotstorm_id: @dotstorm._id}, (err, idea) =>
      expect(err).to.be null
      idea.set("taglist", "this, that, theother")
      expect(_.isEqual idea.tags, ["this", "that", "theother"]).to.be true
      tagset = ["one", "two", "three"]
      idea.set("tags", tagset)
      expect(_.isEqual idea.tags, tagset).to.be true
      idea.save (err) ->
        expect(err).to.be null
        models.Idea.findOne _id: idea._id, (err, doc) ->
          expect(_.isEqual tagset, doc.tags).to.be true
      done()

  it "removes thumbnails with idea", (done) ->
    models.Idea.findOne {dotstorm_id: @dotstorm._id}, (err, idea) =>
      expect(fs.existsSync idea.getDrawingPath("small")).to.be true
      idea.remove (err) =>
        expect(err).to.be null
        expect(fs.existsSync idea.getDrawingPath("small")).to.be false
        done()
