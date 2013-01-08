isDone = true
waitsForDone = ->
  isDone = false
  waitsFor (-> isDone)
done = -> isDone = true

mahId = undefined

describe "Persist and recall models", ->
  beforeEach ->
    @addMatchers
      fail: (expected) ->
        @message = -> expected
        done()
        return false

  it "waits for socket", ->
    waitsFor -> Backbone.getSocket()?

  it "creates a model", ->
    idea = new Idea name: "hooha"
    runs ->
      idea.save {},
        success: (model) ->
          expect(model.get("name")).toEqual("hooha")
          expect(model.id).toBeDefined()
          mahId = model.id
          done()
        error: (err) -> expect(err).fail()
    waitsForDone()

  it "retrieves a model", ->
    idea = new Idea _id: mahId
    runs ->
      expect(idea.id).toBeDefined()
    runs ->
      idea.fetch
        success: (model) ->
          expect(model.get("name")).toEqual("hooha")
          done()
        error: (err) ->
          expect().fail()
    waitsForDone()

  it "fetches a model from a collection", ->
    ideas = new IdeaList
    runs ->
      ideas.fetch
        success: (coll) ->
          match = undefined
          for model in coll.models
            if model.id == mahId
              match = model
          expect(match).toBeDefined()
          done()
        error: (err) -> expect().fail()
    waitsForDone()

  it "fetches a collection with a query", ->
    ideas = new IdeaList
    runs ->
      ideas.fetch
        query: { name: "not found" }
        success: (coll) ->
          expect(coll.length).toEqual(0)
          done()
        error: (err) -> expect().fail()
    waitsForDone()
    runs ->
      ideas.fetch
        query: { name: "hooha" }
        success: (coll) ->
          expect(coll.length).toEqual(1)
          expect(coll.models[0].get("name")).toEqual("hooha")
          done()
        error: (err) -> expect().fail()
    waitsForDone()

  it "fetches a collection with a query by id", ->
    ideas = new IdeaList
    runs ->
      ideas.fetch
        # not found
        query: { _id: "aaaaaaaaaaaaaaaaaaaaaaaa" }
        success: (coll) ->
          expect(coll.length).toEqual(0)
          done()
        error: (err) -> expect().fail()
    waitsForDone()
    runs ->
      ideas.fetch
        query: { _id: mahId }
        success: (coll) ->
          expect(coll.length).toEqual(1)
          expect(coll.models[0].get("name")).toEqual("hooha")
          done()
        error: (err) -> expect().fail()
    waitsForDone()

  it "updates a model", ->
    idea = new Idea _id: mahId
    runs ->
      idea.save {name: "funny"}
        success: (model) ->
          expect(model.get("name")).toEqual("funny")
          done()
        error: (err) -> expect().fail()
    waitsForDone()

  it "deletes a model", ->
    idea = new Idea _id: mahId
    runs ->
      idea.fetch
        success: (model) ->
          model.destroy
            success: done
            error: (err) -> expect().fail()
        error: (err) -> expect().fail()
    waitsForDone()
