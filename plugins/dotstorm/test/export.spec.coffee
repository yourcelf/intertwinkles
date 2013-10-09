expect = require 'expect.js'
config = require "../../../test/test_config"
common = require "../../../test/common"
schema = require("../lib/schema").load(config)
async  = require("async")
_ = require("underscore")
require "better-stack-traces"

describe "exports", ->
  before (done) ->
    common.startUp (server) =>
      @server = server
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "exports json and csv", (done) ->
    async.waterfall [
      (done) ->
        ds = new schema.Dotstorm({
          slug: "export"
          embed_slug: "embed_export"
          name: "The export test"
          topic: "A lengthy description, with commas and \"quotes\"."
        })
        idea_set = {
          a: new schema.Idea({
            votes: 0
            background: "rgb(255, 255, 221)"
            description: "My idea: commas, \"quotes\", and \n carriages."
            drawing: [["pencil", 184, 274, 290, 352]]
            dotstorm_id: ds._id
          })
          b: new schema.Idea({
            votes: 5
            background: "rgb(255, 255, 221)"
            description: "simple"
            tags: ["this", "that", "theother"]
            dotstorm_id: ds._id
          })
          c: new schema.Idea({
            description: "yo dawg"
            background: "rgb(255, 255, 221)"
            dotstorm_id: ds._id
          })
        }
        ds.groups = [
          {ideas: [idea_set.a]},
          {label: "fun label, ov \"course\"", ideas: [idea_set.b, idea_set.c]}
        ]

        async.series [
          (done) -> ds.save(done)
          (done) -> idea_set.a.save(done)
          (done) -> idea_set.b.save(done)
          (done) -> idea_set.c.save(done)
        ], (err) ->
          done(err, ds, idea_set)

      (ds, idea_set, done) ->
        schema.Dotstorm.findOne({_id: ds._id}).populate('groups.ideas').exec (err, doc) ->
          done(err, doc, idea_set)

      (doc, idea_set, done) ->
        expected = {
          slug: "export"
          embed_slug: "embed_export"
          name: "The export test"
          topic: "A lengthy description, with commas and \"quotes\"."
          url: doc.absolute_url
          groups: [
            {
              label: "",
              ideas: [{
                votes: 0
                description: "My idea: commas, \"quotes\", and \n carriages."
                hasDrawing: true
                hasPhoto: false
                urls: {
                  small: config.api_url + idea_set.a.drawingURLs.small
                  medium: config.api_url + idea_set.a.drawingURLs.medium
                  large: config.api_url + idea_set.a.drawingURLs.large
                }
                tags: []
                background: "rgb(255, 255, 221)"
                votes: 0
              }]
            },
            {
              label: "fun label, ov \"course\""
              ideas: [
                {
                  votes: 5
                  description: "simple"
                  hasDrawing: false
                  hasPhoto: false
                  urls: {
                    small: config.api_url + idea_set.b.drawingURLs.small
                    medium: config.api_url + idea_set.b.drawingURLs.medium
                    large: config.api_url + idea_set.b.drawingURLs.large
                  }
                  tags: ["this", "that", "theother"]
                  background: "rgb(255, 255, 221)"
                },
                {
                  votes: 0
                  description: "yo dawg"
                  background: "rgb(255, 255, 221)"
                  hasDrawing: false
                  hasPhoto: false
                  urls: {
                    small: config.api_url + idea_set.c.drawingURLs.small
                    medium: config.api_url + idea_set.c.drawingURLs.medium
                    large: config.api_url + idea_set.c.drawingURLs.large
                  }
                  tags: []
                  background: "rgb(255, 255, 221)"
                  votes: 0
                }
              ]
            }
          ]
        }

        actual = doc.exportJSON()

        expect(expected).to.eql(actual)

        done(null, doc, idea_set)

      (doc, idea_set, done) ->
        expected = [
          [
            "description"
            "votes"
            "group label"
            "tags"
            "url"
            "has photo?"
            "has drawing?"
          ], [
            "My idea: commas, \"quotes\", and \n carriages."
            0
            ""
            ""
            config.api_url + idea_set.a.drawingURLs.large
            "no"
            "yes"
          ], [
            "simple"
            5
            "fun label, ov \"course\""
            "this, that, theother"
            config.api_url + idea_set.b.drawingURLs.large
            "no"
            "no"
          ], [
            "yo dawg"
            0
            "fun label, ov \"course\""
            ""
            config.api_url + idea_set.c.drawingURLs.large
            "no"
            "no"
          ]
        ]
        actual = doc.exportRows()
        expect(expected).to.eql(actual)
        done()
    ], done

