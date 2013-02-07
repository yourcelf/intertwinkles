#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone

FlashTemplate = "
      <%- message %>
      <a href='#' class='close'>&#10006;</a>
"

#
# Flash
#
class FlashMessage extends Backbone.Model
class FlashMessageList extends Backbone.Collection
  model: FlashMessage

class FlashView extends Backbone.View
  template: _.template FlashTemplate
  tagName: 'li'
  events:
    'click .close': 'closeMessage'
  initialize: (flashModel) ->
    @model = flashModel
  render: =>
    @$el.html @template message: @model.get "message"
    @$el.addClass @model.get "level"
    if @model.get("level") != "error"
      setTimeout (=> @closeMessage()), 4000
    this
  closeMessage: (event) =>
    @trigger "close", @model
    @$el.remove()
    return false

class FlashListView extends Backbone.View
  tagName: 'ul'
  initialize: (flashList) ->
    @flashList = flashList
    @flashList.on "add", (model) =>
      fv = new FlashView(model)
      fv.on "close", (model) =>
        @flashList.remove(model)
        return false
      @$el.append fv.render().el


# One global flash list:
window.flashList = new FlashMessageList()
$("#flash").html new FlashListView(flashList).render().el
# Add to global flash list:
window.flash = (level, message) ->
  model = new FlashMessage {level, message}
  flashList.add(model)

