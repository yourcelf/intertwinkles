#
# Sharing permissions control, duplicating logic on server.
# See: lib/intertwinkles.coffee
#
_get_sharing = (model) ->
  return model?.get?("sharing") or model?.sharing or {}

intertwinkles.can_view = (model) ->
  return true if intertwinkles.can_edit(model)
  sharing = _get_sharing(model)
  return true if intertwinkles.parse_date(sharing.public_view_until) > intertwinkles.now()
  return true if _.find(sharing.extra_viewers or [], (e) ->
    e == intertwinkles.user.get("email"))

intertwinkles.can_edit = (model) ->
  sharing = _get_sharing(model)
  # No group? Everyone can edit.
  return true if not sharing.group_id?
  # Even with a group, it might be marked public.
  return true if intertwinkles.parse_date(sharing.public_edit_until) > intertwinkles.now()
  # Otherwise, must be logged in.
  return false if not intertwinkles.is_authenticated()
  # All good if we're in the owning group.
  return true if intertwinkles.groups[sharing.group_id]?
  # All good if explicitly allowed to edit.
  return true if _.find(sharing.extra_editors or [], (e) ->
    e == intertwinkles.user.get("email"))
  return false

intertwinkles.can_change_sharing = (model) ->
  sharing = _get_sharing(model)
  # No group, and no explicit editors, go ahead.
  return true if not sharing.group_id? and (
    (sharing.extra_editors or []).length == 0
  )
  # Otherwise, must be logged in.
  return false unless intertwinkles.is_authenticated()
  # All good if you belong to the group.
  return true if _.find(
    intertwinkles.groups or [],
    (g) -> g._id == sharing.group_id
  )
  # All good if you're an explicit editor.
  return true if _.find(sharing.extra_editors or [], intertwinkles.user.get("email"))
  return false

#
# Sharing control widget
#

sharing_control_template = _.template("""
  <% if (intertwinkles.is_authenticated()) { %>

    <div class='group-options'>
      <% if (_.keys(intertwinkles.groups).length > 0) { %> Belongs to group: <% } %>
        <div class='group-choice'></div>
      <hr>
    </div>

    <span class='public-group-hint'>Add a group to change sharing options.</span><br />

    <div class='all-options'>
      <a href='#' class='change-sharing-options'>Change sharing options</a>

      <div class='public-options'>
        <div class='public-editing'>
            In addition to group members, share with:<br />
            Public: <select name='public_edit_or_view'>
                      <option value=''>No</option>
                      <option value='edit'>can edit</option>
                      <option value='view'>can view</option>
                    </select>
          </label>
          <span class='public-until'>
            until <select name='public_until'>
                    <option value='-1'>Forever</option>
                    <option value='<%- 1000 * 60 * 60 %>'>One hour</option>
                    <option value='<%- 1000 * 60 * 60 * 24 %>'>One day</option>
                    <option value='<%- 1000 * 60 * 60 * 24 * 7 %>'>One week</option>
                  </select>
          </span>
        </div>
        <div class='advertise'>
          <label>
            Show up in public searches?
            <input type='checkbox' name='advertise' />
          </label>
        </div>
      </div>

      <div class='extra-options'>
        <hr>
        <div class='extra'>
          Extra editors (list email addresses):<br />
          <textarea name='extra_editors'></textarea>
          <br />
          Extra viewers (list email addresses):<br />
          <textarea name='extra_viewers'></textarea>
        </div>
        <a href='#' class='toggle-specific-people'>Add specific people</a>
        <hr />
      </div>
    </div>

    <div class='summary'>
      <!--<h4>Sharing summary:</h4>-->
      <b><span class='summary-title'></span></b>
      <div class='summary-content'></div>
    </div>

  <% } else { %>
    <span class='help-inline'>
      Anyone with the URL can edit or view.<br />
      Sign in to change this.
    </span>
  <% } %>
""")

class intertwinkles.SharingFormControl extends Backbone.View
  #
  # A control for editing the sharing settings within a form.
  #
  template: sharing_control_template
  initialize: (options={}) ->
    # Create a deep copy to operate on.
    sharing = options.sharing or {}
    @sharing = {
      group_id: sharing.group_id
      public_edit_until: if sharing.public_edit_until then intertwinkles.parse_date(sharing.public_edit_until) else undefined
      public_view_until: if sharing.public_view_until then intertwinkles.parse_date(sharing.public_view_until) else undefined
      extra_editors: if sharing.extra_editors then (a for a in sharing.extra_editors) else undefined
      extra_viewers: if sharing.extra_viewers then (a for a in sharing.extra_viewers) else undefined
      advertise: sharing.advertise
    }
    @sharing = intertwinkles.normalize_sharing(@sharing)
    # Show the group control at first even if we have a group set already.
    @force_show_group = options.force_show_group or false
    @listenTo intertwinkles.user, "change", @render
  
  render: =>
    @$el.addClass("sharing-controls")
    @$el.html(@template({sharing: @sharing}))
    @renderSummary()
    return unless intertwinkles.is_authenticated()

    @groupChoice?.remove()
    @groupChoice = new intertwinkles.GroupChoice()
    @$(".group-choice").html(@groupChoice.el)
    @groupChoice.render()

    @setValues()
    @addListeners()
    @setInitialVisibility()

  setValues: =>
    @$("#id_group").val(@sharing.group_id) if @sharing.group_id?
    if @sharing.public_edit_until?
      @$("select[name=public_edit_or_view]").val("edit")
    else if @sharing.public_view_until?
      @$("select[name=public_edit_or_view]").val("view")
    public_until = @sharing.public_edit_until or @sharing.public_view_until
    if public_until
      diff = public_until - intertwinkles.now().getTime()
      if diff > 1000 * 60 * 60 * 24 * 365
        @$("select[name=public_until]").val("-1")
      else if diff > 1000 * 60 * 60 * 24
        @$("select[name=public_until]").val(1000 * 60 * 60 * 24 * 7) # one week
      else if diff > 1000 * 60 * 60
        @$("select[name=public_until]").val(1000 * 60 * 60 * 24) # one day
      else
        @$("select[name=public_until]").val(1000 * 60 * 60) # one hour
    if @sharing.extra_editors?
      @$("textarea[name=extra_editors]").val(@sharing.extra_editors.join("\n"))
    if @sharing.extra_viewers?
      @$("textarea[name=extra_viewers]").val(@sharing.extra_viewers.join("\n"))
    @$("input[name=advertise]").attr("checked", @sharing.advertise == true)
  
  addListeners: =>
    next = @renderSummary

    @$(".change-sharing-options").on "click", (event) =>
      event.preventDefault()
      $(event.currentTarget).hide()
      @$(".group-options").show()
      @$(".public-options").show()
      @$(".extra-options").show() if @sharing.group_id?
      @trigger "resize", this

    @$(".toggle-specific-people").on "click", (event) =>
      event.preventDefault()
      extra = @$(".extra")
      if extra.is(":visible")
        extra.hide()
        $("textarea", extra).val("")
        delete @sharing.extra_editors
        delete @sharing.extra_viewers
        $(event.currentTarget).html("Add specific people")
      else
        $(event.currentTarget).html("Remove these")
        extra.show()
      @trigger "resize", this
      next()

    @$("#id_group").on "change", =>
      orig_group_id = @sharing.group_id
      @sharing.group_id = @$("#id_group").val()
      if @sharing.group_id
        @sharing.group_id = @sharing.group_id
        @$("select[name=public_until]").attr("disabled", false)
        @$("select[name=public_edit_or_view]").attr("disabled", false)
        # If switching from no group to group, default to private.
        if not orig_group_id
          @$("select[name=public_edit_or_view]").val("").change()
        @$("input[name=advertise]").attr("disabled", false)
        @$(".extra-options").toggle(@$(".public-options").is(":visible"))
        @$(".public-group-hint").hide()
        @$(".all-options").show()
      else
        delete @sharing.group_id
        delete @sharing.public_view_until
        delete @sharing.public_edit_until
        delete @sharing.extra_viewers
        delete @sharing.extra_editors
        @$("select[name=public_until]").val(-1).attr("disabled", true).change()
        @$(".public-until").show()
        @$("select[name=public_edit_or_view]").val("edit").attr("disabled", true).change()
        @$("input[name=advertise]").attr("checked", false).attr("disabled", true).change()
        @$(".public-group-hint").show()
        @$(".extra-options textarea").val("")
        @$(".extra-options").hide()
        @$(".all-options").hide()
      @trigger "resize", this
      next()

    @$("select[name=public_until], select[name=public_edit_or_view]").on "change", =>
      val = parseInt(@$("select[name=public_until]").val())
      if val == -1
        # 1000 years in the future should be good enough for 'forever'.
        val = 1000 * 60 * 60 * 24 * 365 * 1000
      future = new Date(intertwinkles.now().getTime() + val)
      switch @$("select[name=public_edit_or_view]").val()
        when 'edit'
          @sharing.public_edit_until = future
          @sharing.public_view_until = null
          @$(".public-until, .advertise").show()
        when 'view'
          @sharing.public_edit_until = null
          @sharing.public_view_until = future
          @$(".public-until, .advertise").show()
        when ''
          @sharing.public_edit_until = null
          @sharing.public_view_until = null
          @sharing.advertise = false
          @$("input[name=advertise]").val(false)
          @$(".public-until, .advertise").hide()
      @trigger "resize", this
      next()

    @$("input[name=advertise]").on "change", (event) =>
      @sharing.advertise = @$("input[name=advertise]").is(":checked")
      next()

    @$("textarea[name=extra_editors], textarea[name=extra_viewers]").on "change", =>
      @sharing.extra_editors = _.reject(
        @$("textarea[name=extra_editors]").val().split(/[,\s]+/), (e) -> not e
      )
      @sharing.extra_viewers = _.reject(
        @$("textarea[name=extra_viewers]").val().split(/[,\s]+/), (e) -> not e
      )
      if @sharing.extra_editors.length == 0
        @sharing.extra_editors = null
      if @sharing.extra_viewers.length == 0
        @sharing.extra_viweers = null
      next()

  setInitialVisibility: =>
    @$(".public-options").hide()
    @$("#id_group").change()
    if @$("select[name=public_edit_or_view]").val() == ""
      @$(".public-until, .advertise").hide()
    # By default hide group if it's specified; show it if we've been told to.
    if @sharing.group_id? and not @force_show_group
      @$(".group-options").hide()
    @$(".extra-options").hide()
    @$(".extra").hide()
    if @sharing.extra_editors?.length > 0 or @sharing.extra_viewers?.length > 0
      @$(".toggle-specific-people").click()

  renderSummary: =>
    # Render a natural-language summary of the model's current sharing preferences.
    summary = intertwinkles.sharing_summary(@sharing)
    @$(".summary .summary-content").html(summary.content)
    @$(".summary .summary-title").html(summary.title)

intertwinkles.sharing_summary = (sharing) ->
  perms = []
  short_title = ""
  if not sharing?
    short_title = "Public with secret URL"
    perms.push("Anyone with the link can edit, but it won't show up in search results.")
  else if not sharing.group_id?
    if sharing.advertise
      short_title = "Public wiki"
      icon_class = "icon-globe"
      perms.push("Anyone can find and edit. It will show up in search results.")
    else
      short_title = "Public with secret URL"
      icon_class = "icon-share"
      perms.push("Anyone with the link can edit, but it won't show up in search results.")
  else
    now = intertwinkles.now()
    is_public = false
    group = intertwinkles.groups?[sharing.group_id]
    if group?
      group_list = _.map(group.members, (m) -> intertwinkles.users[m.user].email)
      perms.push("Owned by <acronym title='#{group_list.join(", ")}'>#{group.name}</acronym>.")
    if sharing.public_edit_until?
      if sharing.public_edit_until.getTime() - now.getTime() > 1000 * 60 * 60 * 24 * 365 * 100
        future = ""
      else
        future = " until <nobr>#{sharing.public_edit_until.toString("ddd MMM d, h:mmtt")}</nobr>"
        short_title = "Public " + future
      perms.push("Anyone with the URL can edit this#{future}.")
      is_public = true
      if sharing.advertise
        short_title = "Public wiki"
        icon_class = "icon-globe"
      else
        short_title = "Public with secret URL"
        icon_class = "icon-share"
    else if sharing.public_view_until?
      if sharing.public_view_until.getTime() - now.getTime() > 1000 * 60 * 60 * 24 * 365 * 100
        future = ""
      else
        future = "until #{sharing.public_view_until.toString("ddd MMM d, h:mmtt")}"
      perms.push("Anyone with the link can view this#{future}.")
      is_public = true
      if sharing.advertise
        short_title = "Public on the web"
        icon_class = "icon-globe"
      else
        short_title = "Public with secret URL"
        icon_class = "icon-share"
    else
      short_title = "Private to #{group.name}"
      icon_class = "icon-lock"

    if sharing.extra_editors?.length > 0
      other_editors = _.difference(sharing.extra_editors, group_list)
    else
      other_editors = []
    if sharing.extra_viewers?.length > 0
      other_viewers = _.difference(sharing.extra_viewers, group_list, other_editors)
    else
      other_viewers = []
    if other_editors.length > 0
      perms.push("Extra editors: <i>#{other_editors.join(", ")}</i>.")
    if other_viewers.length > 0
      perms.push("Extra spectators: <i>#{other_viewers.join(", ")}</i>.")
    if not is_public
      perms.push("All others, and people who aren't signed in, can't view or edit.")
  if is_public
    if sharing.advertise
      perms.push("The link will show up in public search results.")
    else if sharing.group_id?
      perms.push("The link will show up in group members' search results only.")
    else
      perms.push("The link won't show up in search results.")
  return {
    title: short_title
    content: perms.join("<br />")
    icon_class: icon_class
  }

intertwinkles.normalize_sharing = (sharing) ->
  # Normalize sharing
  return {} if not sharing?
  now = intertwinkles.now()
  if sharing.public_edit_until?
    # Remove stale public edit until
    sharing.public_edit_until = intertwinkles.parse_date(sharing.public_edit_until)
    if sharing.public_edit_until < now
      delete sharing.public_edit_until
  if sharing.public_view_until?
    # Remove stale public view until
    sharing.public_view_until = intertwinkles.parse_date(sharing.public_view_until)
    if sharing.public_view_until < now
      delete sharing.public_view_until
  if sharing.extra_editors?.length == 0
    # Remove empty extra editors.
    delete sharing.extra_editors
  if sharing.extra_viewers?.length == 0
    # Remove empty extra viewers.
    delete sharing.extra_viewers
  if sharing.group_id? and not (sharing.public_edit_until? or sharing.public_view_until?)
    # Can't advertise unless it's public.
    sharing.advertise = false
  return sharing


sharing_settings_button_template = _.template("""
  <div class='sharing-settings-button'>
    <% if (can_email) { %>
      <a class='btn btn-success email-group'>
        <i class='icon-envelope'></i> Email<span class='hidden-phone'> Group</span>
      </a><% } %><a
        class='btn btn-success open-sharing'><i class='<%- icon_class %>'></i> Sharing</a>
  </div>
""")
sharing_settings_modal_template = _.template("""
  <div class='modal hide fade'>
    <div class='modal-header'>
      <button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>
      <h3>Sharing</h3>
    </div>
    <form class='form-horizontal'>
      <div class='modal-body'>
        <div class='sharing-controls'></div>
      </div>
      <div class='modal-footer'>
        <div class='url-to-share pull-left'>
          Share this:
          <div style='display: inline-block; vertical-align: top; position: relative;'>
            <input readonly type='text' class='url' value='<%- window.location.href %>' /><br/>
            <a href='#' class='pull-left shrink-link' title='Shorten URL'>shorten</a>
            <a href='#' class='show-qrcode' title='Show barcode'>qrcode</a>
            <div class='qrcode'></div>
          </div>

        </div>
        <input type='submit' class='btn btn-primary btn-large' value='Save' />
      </div>
    </form>
  </div>
""")

email_group_modal_template = _.template("""
  <div class='modal hide fade email-group'>
    <form>
      <div class='modal-header'>
        <button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>
        <h3>Send an email to <%- group.name %></h3>
      </div>
      <div class='modal-body'>
        <table class='email-sender'>
          <tr>
            <th>To:</th>
            <td>
              <ul class='email-list'>
                <% for (var i = 0; i < group.members.length; i++) { %>
                  <li class='inline-user'
                    title="<%- intertwinkles.users[group.members[i].user].email %>"
                    data-placement="bottom">
                      <%= intertwinkles.inline_user(group.members[i].user, null, "tiny") %>
                  </li>
                <% } %>
              </ul>
            </td>
          </tr>
          <tr>
            <th>Subject:</th>
            <td><input type='text' name='subject' value='<%- $("title").html() %>' style='width: 95%;'/></td>
          </tr>
          <tr>
            <td colspan='2'>
              <textarea name='body' rows=7 cols=60 style='width: 95%;'>Hey <%- group.name %>,

  Check this out!
  <%- window.location.href %>

  In cooperation,
  <%- intertwinkles.user.get("name") %></textarea>
            </td>
          </tr>
        </table>
      </div>
      <div class='modal-footer'>
        <a class='btn close pull-left' data-dismiss='modal' href='#'>Close</a>
        <input type='submit' class='btn btn-primary btn-large' value='Send Email' />
      </div>
    </form>
  </div>
""")

class intertwinkles.SharingSettingsButton extends Backbone.View
  # A control that briefly summarizes the sharing preferences for a document,
  # and invokes a form to edit them.
  template: sharing_settings_button_template
  sharingSettingsModalTemplate: sharing_settings_modal_template
  emailGroupModalTemplate: email_group_modal_template
  events:
    'click .open-sharing': 'sharingSettingsModal'
    'click .email-group': 'emailGroupModal'

  initialize: (options={}) ->
    @model = options.model
    @application = options.application
    @listenTo @model, "change:sharing", @render
    @listenTo intertwinkles.user, "change", @render

  render: =>
    @read_only = not intertwinkles.can_change_sharing(@model)
    @can_email = !!intertwinkles.groups?[@model.get("sharing")?.group_id]
    summary = intertwinkles.sharing_summary(intertwinkles.normalize_sharing(
      @model.get("sharing")
    ))
    @$el.html(@template({
      icon_class: summary.icon_class
      can_email: @can_email
    }))
    popover_content = summary.content
    if @read_only
      @$(".open-sharing").addClass("disabled")
      popover_content += "<br /><i>Sign in as an owner of this to change settings.</i>"
    else
      popover_content += "<br /><i>Click to change settings.</i>"
        
    @$(".open-sharing").popover({
        placement: "bottom"
        html: true
        title: summary.title
        content: popover_content
        trigger: "hover"
      })

  sharingSettingsModal: (event) =>
    event.preventDefault()
    return if @read_only
    @modal?.modal("hide")
    modal = $(@sharingSettingsModalTemplate())
    $("body").append(modal)
    modal.modal('show').on('hidden', -> modal.remove())
    @sharing = new intertwinkles.SharingFormControl(sharing: @model.get("sharing"))
    $(".sharing-controls", modal).html(@sharing.el)
    @sharing.render()
    $("form", modal).on "submit", @save
    $(".shrink-link", modal).on 'click', (event) =>
      event.preventDefault()
      input = modal.find("input.url")
      if input.hasClass("short")
        $(event.currentTarget).html("shorten")
        input.val(input.attr("data-long-url")).removeClass("short")
      else
        $(event.currentTarget).html("unshorten")
        input.attr("data-long-url", input.val()).addClass("short")
        if input.attr("data-short-url")
          input.val(input.attr("data-short-url"))
        else
          input.addClass("loading")
          intertwinkles.get_short_url {
            path: input.val(),
            application: @application
          }, (err, result) ->
            input.removeClass("loading")
            if err?
              console.error(err)
              flash "error", "Server error!  oh noes.."
            else
              input.attr("data-short-url", result).val(result)

    $(".qrcode", modal).qrcode({
      width: 150, height: 150, text: $("input.url", modal).val()
    }).css({
      width: "150px"
      height: "150px"
      position: "absolute"
      right: "0px"
      bottom: "24px"
      display: "none"
    })
    $(".show-qrcode", modal).on "click", (event) ->
      event.preventDefault()
      $(".qrcode", modal).toggle()
      
    @sharing.on "resize", -> $(window).resize()
    @modal = modal

  emailGroupModal: (event) =>
    event.preventDefault()
    return unless @can_email
    @modal?.modal("hide")
    group = intertwinkles.groups[@model.get("sharing").group_id]
    modal = $(@emailGroupModalTemplate({group: group}))
    $("body").append(modal)
    modal.modal('show').on('hidden', -> modal.remove())
    modal.find("form").on "submit", (event) =>
      event.preventDefault()
      subject = $.trim($("input[name=subject]", modal).val())
      body = $.trim($("textarea[name=body]", modal).val())
      unless subject and body
        alert("Please enter a subject and a message.")
        return
      intertwinkles.socket.once "email_sent", (data) ->
        modal.modal("hide")
        flash "success", "Email sent to #{group.members.length} group members."
        modal.modal("hide")
      intertwinkles.socket.send "email_group", {
        entity: @model.id
        group_id: @model.get("sharing").group_id
        subject: subject
        body: body
      }
      modal.find("input[type=submit]").attr("disabled", true).addClass("loading")
    @modal = modal

  close: =>
    @modal.modal('hide')

  save: (event) =>
    event.preventDefault()
    $("input[type=submit]", @modal).addClass("loading")
    @trigger "save", @sharing.sharing
    return false

