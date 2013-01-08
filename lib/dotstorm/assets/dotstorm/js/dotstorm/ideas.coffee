class ds.ShowIdeaGroup extends Backbone.View
  template: _.template $("#dotstormSmallIdeaGroup").html() or ""
  editTemplate: _.template $("#dotstormSmallIdeaGroupEditLabel").html() or ""
  events:
    'click    .grouplabel': 'editLabel'
    'touchend .grouplabel': 'editLabel'
    'click        .cancel': 'cancelEdit'
    'touchend     .cancel': 'cancelEdit'
    'submit          form': 'saveLabel'

  initialize: (options) ->
    @group = options.group
    @ideaViews = options.ideaViews
    @position = options.position

  editLabel: (event) =>
    unless @editing
      event.stopPropagation()
      event.preventDefault()
      @editing = true
      $(event.currentTarget).html @editTemplate
        label: @group.label or ""
      @$("input[type=text]").select()

  cancelEdit: (event) =>
    event.stopPropagation()
    event.preventDefault()
    @editing = false
    @render()
    return false
  
  saveLabel: (event) =>
    event.stopPropagation()
    event.preventDefault()
    @editing = false
    @group.label = @$("input[type=text]").val()
    @trigger "change:label", @group
    return false

  render: =>
    @$el.html @template
      showGroup: @ideaViews.length > 1
      label: @group.label
      group_id: @group._id
    @$el.addClass("masonry")
    if @ideaViews.length > 1
      @$el.addClass("group")
    @$el.attr({
      "data-group-id": @group._id
      "data-group-position": @position
    })
    container = @$(".ideas")
    container.css("height", "100%")
    _.each @ideaViews, (view, i) =>
      container.append view.el
      view.$el.attr("data-idea-position", i)
      view.render()
    this

class ds.ShowIdeaSmall extends Backbone.View
  template: _.template $("#dotstormSmallIdea").html() or ""
  initialize: (options) ->
    @model = options.model
    @size = options.size or "medium"
    @model.on "change:tags", @render
    @model.on "change:imageVersion", @render
    @model.on "change:description", @render
    @model.on "change:photo", @render

  render: =>
    args = _.extend
      tags: []
      description: ""
    , @model.toJSON()
    @$el.html @template args
    @$el.attr("data-id", @model.id)
    @$el.addClass("smallIdea")
    @renderVotes()

  renderVotes: =>
    @$(".votes").html new ds.VoteWidget({
      idea: @model
      readOnly: true
      hideOnZero: true
    }).render().el

class ds.ShowIdeaBig extends Backbone.View
  template: _.template $("#dotstormBigIdea").html() or ""
  editorTemplate: _.template $("#dotstormInPlaceInput").html() or ""
  events:
    'mousedown .shadow': 'close'
    'touchstart .shadow': 'close'

    'mousedown .close': 'close'
    'touchstart .close': 'close'

    'mousedown .next': 'next'
    'touchstart .next': 'next'

    'mousedown .prev': 'prev'
    'touchstart .prev': 'prev'

    'mousedown .edit': 'edit'
    'touchstart .edit': 'edit'

    'click .tags .clickToEdit': 'editTags'
    'submit .tags form': 'saveTags'

    'mousedown .note': 'nothing'
    'touchstart .note': 'nothing'

  initialize: (options) ->
    @model = options.model
    @model.on "change:description", @render
    @model.on "change:tags", @render
    @model.on "change:background", @render
    @model.on "change:drawing", @render
    @model.on "change:photo", @render
    @model.on "change:sharing", @render
    intertwinkles.user.on "change", @render

  remove: =>
    intertwinkles.user.off "change", @render
    super()

  render: =>
    #console.debug "render big", @model.get "imageVersion"
    args = _.extend {
      tags: []
      description: ""
      hasNext: @model.showNext?
      hasPrev: @model.showPrev?
    }, @model.toJSON()
    @$el.html @template args
    @$el.addClass("bigIdea")
    resize = =>
      noteHeight = @$(".note").outerHeight(true) - @$(".canvasHolder").outerHeight(true)
      maxImgHeight = $(window).height() - noteHeight
      @$(".canvasHolder").css("max-height", $(window).height() - noteHeight)
      @$(".note").css("width", Math.min(640, maxImgHeight))
      # hack for mobile which doesn't support 'fixed'
      @$(".note")[0].scrollIntoView()
    @$(".note img").on "load", resize
    resize()
    @renderVotes()
    $(window).on "resize", resize
    unless intertwinkles.can_edit(ds.model)
      @$(".clickToEdit").removeClass("clickToEdit")
      @$(".toolbar .edit").hide()
    this

  renderVotes: =>
    @$(".vote-widget").html new ds.VoteWidget(idea: @model).render().el

  close: (event) =>
    if event?
      event.preventDefault()
      event.stopPropagation()
    @trigger "close", this
    @$el.remove()
    ds.app.navigate "/dotstorm/d/#{ds.model.get("slug")}/"
    return false

  nothing: (event) =>
    event.stopPropagation()
    #event.preventDefault()

  next: (event) =>
    event.stopPropagation()
    @close()
    @model.showNext() if @model.showNext?
    return false

  prev: (event) =>
    event.stopPropagation()
    @close()
    @model.showPrev() if @model.showPrev?
    return false

  edit: (event) =>
    event.stopPropagation()
    event.preventDefault()
    ds.app.navigate "/dotstorm/d/#{ds.model.get("slug")}/edit/#{@model.id}/",
      trigger: true
    return false

  editTags: (event) =>
    event.stopPropagation()
    @$(event.currentTarget).replaceWith @editorTemplate
      text: (@model.get("tags") or []).join(", ")
    @$("input[type=text]").select()
    return false

  saveTags: (event) =>
    val = @$(".tags input[type=text]").val()
    @model.save {tags: @model.cleanTags(val)}, {
      success: (model) =>
      error: (model, err) =>
        console.error "error", err
        flash "error", err
    }
    return false
