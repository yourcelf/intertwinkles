
class ds.VoteWidget extends Backbone.View
  template: _.template $("#dotstormVoteWidget").html() or ""
  events:
    'touchstart   .upvote': 'upVote'
    'mousedown    .upvote': 'upVote'
    'touchstart .downvote': 'downVote'
    'mousedown  .downvote': 'downVote'
  initialize: (options) ->
    @idea = options.idea
    @listenTo @idea, "change:votes", @update
    @readOnly = options.readOnly
    @hideOnZero = options.hideOnZero
    if @readOnly
      @undelegateEvents()
    @listenTo intertwinkles.user, "change", @render
    @listenTo ds.model, "change:sharing", @render

  render: =>
    #console.debug "render votewidget", @idea.id
    @$el.addClass("vote-widget")
    @$el.html @template(readOnly: @readOnly)
    @update()
    unless intertwinkles.can_edit(ds.model)
      @$(".upvote, .downvote").hide()
    this

  update: =>
    votes = @idea.get("votes") or 0
    @$(".vote-count").html votes
    if @hideOnZero
      if votes == 0
        @$el.hide()
      else
        @$el.show()

  upVote: (event) =>
    return @changeVote(event, 1, ".upvote")
  downVote: (event) =>
    return @changeVote(event, -1, ".downvote")

  changeVote: (event, direction, controlSelector) =>
    event.stopPropagation()
    event.preventDefault()
    # Must copy array; otherwise change events don't fire properly.
    if @timeoutFor == controlSelector
      return false
    @idea.save {
        votes: Math.max(0, (@idea.get("votes") or 0) + direction)
      }, {
        error: (model, err) =>
          console.error "error", err
          flash "error", "Error saving vote: #{err.error}"
      }
    selectorList = [".vote-count"]
    if controlSelector? then selectorList.push(controlSelector)
    selectors = selectorList.join(", ")
    @$(selectors).addClass("active")
    @timeoutFor = controlSelector
    setTimeout =>
      @$(selectors).removeClass("active")
      @timeoutFor = null
    , 2000
    return false
