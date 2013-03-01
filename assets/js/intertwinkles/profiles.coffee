edit_new_profile_template = _.template("""
<form class='new-profile-form'>
  <div class='modal-body'>
    <button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>
    <h3 style='text-align: center;'>Ready in 1, 2, 3:</h3><br />
    <div class='control-group'>
      <b>1: What is your name?</b><br />
      <div class='controls'></div><!-- keep this for a target for validation errors. -->
      <input type='text' name='name' value='<%= name %>' />
    </div>
    <div class='control-group'>
      <b>2: What is your favorite color?</b><br />
      <div class='controls'></div><!-- keep this for a target for validation errors. -->
      <div class='help-text color-label'></div>
      <input type='text' name='color' value='<%= color %>' class='color' />
    </div>
    <div class='control-group'>
      <b>3. Which icon do you like the best?</b><br />
      <div class='controls'></div><!-- keep this for a target for validation errors. -->
      <div class='image-chooser'></div>
    </div>
  </div>
  <div class='modal-footer'>
    <input type='submit' value='OK, Ready, Go!' class='btn btn-primary btn-large' />
  </div>
</form>
""")

class intertwinkles.EditNewProfile extends intertwinkles.BaseModalFormView
  template: edit_new_profile_template
  initialize: ->
    icon = intertwinkles.user.get("icon")
    super({
      context: {
        name: intertwinkles.user.get("name")
        color: icon?.color or ""
        icon_id: icon?.id or ""
      }
      validation: [
        ["[name=name]", ((v) -> v or null), "Please choose a name."],
        ["[name=icon]", ((v) -> v or null), "Please choose an icon."],
        ["[name=color]", (v) ->
          if v and /[a-f0-9A-F]{6}/.exec(v)? then v else null
        , "Invalid color"]
      ]
    })
    @on "submitted", @saveProfile

  render: =>
    super()
    @addView(".image-chooser", new intertwinkles.IconChooser({
      chosen: intertwinkles.user.get("icon")?.id
    }))
    @$(".color").on "change", =>
      val = @$(".color").val()
      @$(".color-label").css("color", "#" + val).html(intertwinkles.match_color(val))
    @$(".color").change()
    this

  saveProfile: (cleaned_data) =>
    intertwinkles.socket.once "profile_updated", (data) =>
      @$("input[type=submit]").removeClass("loading")
      if data.error?
        flash "error", "Oh Noes... Server errorrrrrrr........."
        @$el.modal("hide")
        @trigger "done"
      else
        intertwinkles.user.set(data.model)
        @$el.modal("hide")
        @trigger "done"

    intertwinkles.socket.send "edit_profile", {
      callback: "profile_updated"
      model: {
        email: intertwinkles.user.get("email")
        name: cleaned_data.name
        icon: { id: cleaned_data.icon, color: cleaned_data.color }
      }
    }
    @remove()

#
# Icon Chooser widget
#

icon_chooser_template = _.template("""
  <input name='icon' id='id_icon' value='<%= chosen %>' type='hidden' />
  <div class='profile-image-chooser'><img src='/static/img/spinner.gif' alt='Loading...'/></div>
  <div>
    <a class='attribution-link' href='#{INTERTWINKLES_APPS.www.url}/profiles/icon_attribution/'>
      About these icons
    </a>
  </div>
  <div style='clear: both;'></div>
""")

class intertwinkles.IconChooser extends Backbone.View
  template: icon_chooser_template
  chooser_image: "/static/js/intertwinkles_icon_chooser.png"
  initialize: (options={}) ->
    @chosen = options.chosen

  render: =>
    @$el.html(@template(chosen: @chosen or ""))
    $.get "/static/js/intertwinkles_icon_chooser.json", (data) =>
      icon_holder = @$(".profile-image-chooser")
      icon_holder.html("")
      _.each data, (def, i) =>
        cls = "profile-image"
        cls += " chosen" if @chosen == def.pk
        icon = $("<div/>").html(def.name).attr({ "class": cls }).css {
          "background-image": "url('#{@chooser_image}')"
          "background-position": "#{-32 * i}px 0px"
        }
        icon.on "click", =>
          @$(".profile-image.chosen").removeClass("chosen")
          icon.addClass("chosen")
          @$("input[name=icon]").val(def.pk)
          @chosen = def.pk
        icon_holder.append(icon)
      icon_holder.append("<div style='clear: both;'></div>")
    jscolor.bind()

icon_chooser_lite_template = _.template("""
  <input type='hidden' id='id_icon' name='icon' value='<%= chosen %>' />
  <input type='text' id='id_icon_chooser' value='' disabled style='float: left;'/>
  <span class='chosen-image' style='float: left;'></span>
""")

class intertwinkles.IconChooserLite extends Backbone.View
  template: icon_chooser_lite_template
  chooser_data:  "/static/js/intertwinkles_icon_chooser.json"
  chooser_image: "/static/js/intertwinkles_icon_chooser.png"
  events:
    'keydown input': 'keyup'

  initialize: (options={}) ->
    @chosen = options.chosen

  render: =>
    @$el.html(@template(chosen: @chosen))
    $.get @chooser_data, (data) =>
      intertwinkles.icon_defs = {}
      for entry in data
        intertwinkles.icon_defs[entry.pk + ""] = entry.name
      @$("#id_icon_chooser").attr("disabled", false)
      @$("#id_icon_chooser").typeahead({
        source: @source
        matcher: @matcher
        sorter: @sorter
        updater: @updater
        highlighter: @highlighter
      })

      @updater(@chosen + "") if @chosen?

  keyup: (event) =>
    if @$("#id_icon_chooser").val() != intertwinkles.icon_defs[@chosen]
      @$(".chosen-image").html("")
      @$("#id_icon").val("")

  source: (query) ->
    return ("#{pk}" for pk,name of intertwinkles.icon_defs)

  matcher: (item) ->
    return intertwinkles.icon_defs[item].toLowerCase().indexOf(@query.toLowerCase()) != -1

  sorter: (items) ->
    return _.sortBy items, (a) -> intertwinkles.icon_defs[a]

  updater: (item) =>
    @$("#id_icon").val(item)
    @$(".chosen-image").html(@build_icon(item))
    @$("#id_icon_chooser").val(intertwinkles.icon_defs[item])
    return intertwinkles.icon_defs[item]

  highlighter: (item) ->
    name = intertwinkles.icon_defs[item]
    query = this.query.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')
    highlit = name.replace new RegExp('(' + query + ')', 'ig'), ($1, match) ->
      return '<strong>' + match + '</strong>'
    res = $("<div></div>")
    res.append(intertwinkles.IconChooserLite.prototype.build_icon(item))
    res.append("&nbsp;")
    res.append(highlit)
    return res

  build_icon: (pk) =>
    name = intertwinkles.icon_defs[pk]
    return $("<div></div>").html(name).css({
      "font-size": "0"
      "vertical-align": "middle"
      "display": "inline-block"
      "width": "32px"
      "height": "32px"
      "background-image": "url('#{@chooser_image}')"
      "background-position": "#{-32 * (parseInt(pk) - 1)}px 0px"
    })
