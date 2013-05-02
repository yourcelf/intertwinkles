class ds.Intro extends intertwinkles.BaseView
  template: _.template $("#intro").html()
  events:
    'click .softnav': 'softNav'
  render: =>
    @$el.html(@template())
    this

class ds.EditDotstorm extends intertwinkles.BaseView
  chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890"
  template: _.template $("#createTemplate").html()
  events:
    'click .show-add-form': 'showForm'
    'submit form':          'submit'
    'keyup [name=name]':    'changeName'
    'keyup [name=slug]':    'changeSlug'

  initialize: (options={}) ->
    super()
    @_slugIsCustom = false
    randomChar = =>
      @chars.substr parseInt(Math.random() * @chars.length), 1
    @randomSlug = (randomChar() for i in [0...12]).join("")
    @model = options.model or new ds.Dotstorm()

  validate: =>
    return @validateFields "form", [
      ["#id_slug", ((val) =>
        unless @slugUnavailable
          return $.trim(val) or @randomSlug
        return null
      ), "This name is not available."],
      ["#id_name", ((val) => $.trim(val) or ""), ""],
      ["#id_sharing", ((val) => @sharingControl.sharing), "", "sharing"],
    ]

  render: =>
    @$el.html @template(model: @model.toJSON(), randomSlug: @randomSlug)
    @sharingControl?.remove()
    @sharingControl = new intertwinkles.SharingFormControl()
    @addView("#sharingControl", @sharingControl)
    this

  showForm: (event) =>
    event.preventDefault()
    @$(".show-add-form").hide()
    @$("form").show()

  submit: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      @model.save({
        name: cleaned_data.name
        slug: cleaned_data.slug
        sharing: cleaned_data.sharing
      }, {
        success: (model) =>
          @trigger("save", model)
        error: (err) =>
          flash "error", "Sorry, there has been a server errror..."
          console.log arguments
      })

  changeName: (event) =>
    unless @_slugIsCustom
      slug = intertwinkles.slugify(@$("[name=name]").val())
      @$("[name=slug]").val(slug)
      @checkSlug(slug)

  changeSlug: (event) =>
    val = @$("[name=slug]").val()
    @_slugIsCustom = val != ""
    @checkSlug(val)

  checkSlug: (val) =>
    val or= @randomSlug
    @$(".slug-val").html("#{encodeURIComponent(val)}")
    if val and val != @model.get("slug")
      parent = @$("[name=slug]").closest(".control-group")
      intertwinkles.socket.send "dotstorm/check_slug", {slug: val}
      intertwinkles.socket.once "dotstorm:check_slug", (data) =>
        parent.removeClass('error')
        parent.find(".error-msg").remove()
        if not data.available
          @slugUnavailable = true
          @$(".dotstorm-url").hide()
          parent.addClass('error')
          @$("#id_slug").after(
            "<span class='help-inline error-msg'>Name not available</span>"
          )
        else
          @slugUnavailable = false
          @$(".dotstorm-url").show()
