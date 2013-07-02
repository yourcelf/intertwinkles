#
# User menu
#

user_menu_template = _.template("""
  <a class='user-menu dropdown-toggle' href='#' data-toggle='dropdown' role='button'>
    <% if (user.icon && user.icon.tiny) { %>
      <img src='<%- user.icon.tiny %>' />
    <% } else { %>
      <i class='icon-user'></i>
    <% } %>
    <span class='hidden-phone'>
      <%- user.name %>
    </span>
    <b class='caret'></b>
  </a>
  <ul class='dropdown-menu' role='menu'>
    <li><a tabindex='-1' href='<%- INTERTWINKLES_APPS.www.url %>/profiles/edit'><i class='icon icon-cog'></i> Settings</a></li>
    <li class='divider'></li>
    <li><a tabindex='-1' href='<%- INTERTWINKLES_APPS.www.url %>/feedback/'><i class='icon-gift'></i> Feedback</a></li>
    <li class='divider'></li>
    <li><a tabindex='-1' class='sign-out' href='#'>Sign out</a></li>
  </ul>
""")
class intertwinkles.UserMenu extends Backbone.View
  tagName: 'li'
  template: user_menu_template
  events:
    'click .sign-out': 'signOut'

  initialize: ->
    @listenTo intertwinkles.user, "change", @render

  render: =>
    @$el.addClass("dropdown")
    if intertwinkles.is_authenticated()
      @$el.html(@template(user: intertwinkles.user.toJSON()))
    else
      @$el.html("")
    @setAuthFrameVisibility()

  setAuthFrameVisibility: =>
    if intertwinkles.is_authenticated()
      $(".auth_button").hide()
    else
      $(".auth_button").show()

  signOut: (event) =>
    event.preventDefault()
    intertwinkles.request_logout()

#
# Room users menu
#

room_users_menu_template = _.template("""
  <a class='room-menu dropdown-toggle btn' href='#' data-toggle='dropdown'
     title='People in this room'>
    <i class='icon-user'></i><span class='count'></span>
    <b class='caret'></b>
  </a>
  <ul class='dropdown-menu' role='menu'></ul>
""")
room_users_menu_item_template = _.template("""
  <li><a>
    <% if (icon) { %>
      <img src='<%- icon.tiny %>' />
    <% } else { %>
      <i class='icon icon-user'></i>
    <% } %>
    <%- name %>
  </a></li>
""")

class intertwinkles.RoomUsersMenu extends Backbone.View
  tagName: "li"
  template: room_users_menu_template
  item_template: room_users_menu_item_template

  initialize: (options={}) ->
    @room = options.room
    @listenTo intertwinkles.socket, "room_users", @roomList
    @list = []
    @connect()

  connect: =>
    intertwinkles.socket.send "join", {room: @room}

  remove: =>
    intertwinkles.socket.send "leave", {room: @room}
    super()

  roomList: (data) =>
    return if data.room != @room
    @list = data.list
    if data.anon_id?
      @anon_id = data.anon_id
    @renderItems()
    
  render: =>
    @$el.addClass("room-users dropdown")
    @$el.html @template()
    @renderItems()

  renderItems: =>
    @$(".count").html(@list.length)
    @menu = @$(".dropdown-menu")
    @menu.html("")
    for item in @list
      self = item.anon_id == @anon_id
      context = _.extend {self}, item
      if self
        @menu.prepend(@item_template(context))
      else
        @menu.append(@item_template(context))
    @menu.prepend("<li><a>Online now:</a></li>")

#
# Toolbar
#

intertwinkles.build_toolbar = (destination, options) ->
  toolbar = new intertwinkles.Toolbar(options)
  $(destination).html(toolbar.el)
  toolbar.render()
  toolbar.setAuthFrameVisibility()
  intertwinkles.twunklify($(destination))

toolbar_template = _.template("""
  <div class='navbar navbar-top nav'>
    <div class='navbar-inner'>
      <div class='container-fluid'>
        <ul class='nav pull-right'>
          <li class='notifications dropdown'></li>
          <li class='user-menu dropdown'></li>
          <li class='auth_button'>
            <a href='#' class='sign-in'><img src='/static/img/sign_in_blue.png' /></a>
          </li>
        </ul>
        <div class='home-link pull-left'>
          <a class='brand' href='/' role='button' id='dlogo'>
            <span class='visible-phone'>
              <img src='/static/img/star-icon.png' alt='IT' style='max-height: 24px;'/>
              <span class='label' style='font-size: 50%;'>BETA</span>
            </span>
            <span class='hidden-phone'>
              Inter<span class='intertwinkles'>Twinkles</span>
              <span class='label' style='font-size: 50%;'>BETA</span>
            </span>
          </a>
        </div>
        <div class='appmenu'>
          <div class='appmenu-content'>
            <div class='form'>
              <form class='form-search'
                    action='<%- INTERTWINKLES_APPS.www.url %>/search/'
                    method='GET'>
                <% if (window.location.pathname != "/") { %>
                <a href='/'>&larr; Groups</a>
                <% } %>
                <div class='input-append'>
                  <input class='input-medium search-query' type='text' name='q' placeholder='Search'/>
                  <button class='btn' type='submit'>
                    <i class='icon-search' title='Search'></i>
                  </button>
                </div>
              </form>
            </div>

            <% if (intertwinkles.is_authenticated()) { %>
              <div class='document-list-holder-holder'>
                <em>Recent things</em><br />
                <div class='documents-list loading'></div>
                <a class='more' href='/'>More...</a>
              </div>
            <% } else { %>
              Sign in to see your group's stuff.
            <% } %>
            <div style='clear: both;'></div>
            <hr>
            <ul class='nav'>
              <% _.each(apps, function(app, i) { %>
                <li class='<%- app.class %>'>
                  <a href='<%- app.url + "/" %>'>
                    <img src='<%- app.image %>' alt='<%- app.name %>' /><br />
                    <%- app.name %>
                  </a>
                </li>
              <% }); %>
            </ul>
          </div>
        </div>
        <div class='appmenu-toggle' title='Documents, search, and apps'>
          <i class='icon-th-list'></i><i class='icon-search'></i>
        </div>
      </div>
    </div>
  </div>
""")

class intertwinkles.Toolbar extends Backbone.View
  template: toolbar_template
  events:
    'click .sign-in':  'signIn'
    'click      .appmenu-toggle': 'toggleAppmenu'
    'touchstart .appmenu-toggle': 'toggleAppmenu'
    'click                input': 'stopPropagation'
    'touchstart           input': 'stopPropagation'

  initialize: (options={}) ->
    @applabel = options.applabel
    @active_name = options.active_name or INTERTWINKLES_APPS[@applabel].name
    $('html').on('click.dropdown.data-api', @_hideAppmenu)
    @listenTo intertwinkles.socket, "recent_docs", @updateDocs
    @listenTo intertwinkles.user, "login", @render

  stopPropagation: (event) ->
    event.stopPropagation()

  remove: =>
    @user_menu?.remove()
    @notification_menu?.remove()
    $('html').off('click.dropdown.data-api', @_hideAppmenu)
    super()

  render: =>
    apps = []
    thisapp = null
    for label, app of INTERTWINKLES_APPS
      menu_app = _.extend {}, app
      menu_app.class = if label == @applabel then "active" else ""
      if label != "www"
        apps.push(menu_app)

    @$el.html @template({
      apps: apps
      active_name: @active_name
    })

    @user_menu?.remove()
    @user_menu = new intertwinkles.UserMenu()
    @$(".user-menu.dropdown").replaceWith(@user_menu.el)
    @user_menu.render()

    @notification_menu?.remove()
    @notification_menu = new intertwinkles.NotificationMenu()
    @$(".notifications").replaceWith(@notification_menu.el)
    @notification_menu.render()

    unless @doc_list?
      @doc_list = new intertwinkles.DocumentList({docs: @_docs})
    @$(".documents-list").html(@doc_list.el)
    @updateDocs()
    this

  updateDocs: (data) =>
    if data?.docs?
      @_docs = data.docs
    if @doc_list?
      @doc_list.docs = @_docs
      @doc_list.render()
      @$(".documents-list").removeClass("loading")

  fetchDocs: =>
    if intertwinkles.is_authenticated()
      intertwinkles.socket.send "get_recent_docs"

  setAuthFrameVisibility: =>
    @user_menu.setAuthFrameVisibility()

  signIn: (event) =>
    event.preventDefault()
    intertwinkles.request_login()

  toggleAppmenu: (event) =>
    if event.type == "touchstart"
      @_isTouch = true
    else if @_isTouch
      return
    menu = @$(".appmenu")
    if menu.is(":visible")
      @_hideAppmenu(event)
    else
      event.preventDefault()
      event.stopPropagation()
      menu.show()
      @fetchDocs()

  _hideAppmenu: (event) =>
    @$(".appmenu").hide()


#
# Footer
#

footer_template = _.template("""
<div class='bg'>
  <img src='/static/img/coop-world.png' alt='Flavor image' />
</div>
<div class='container-fluid collapsible'>
  <div class='ramp'></div>
  <div class='footer-content'>
    <div class='row-fluid'>
      <div class='span4 about-links'>
        <h2>About</h2>
        <ul>
          <li><a href='/about/'>About</a></li>
          <li><a href='/about/starting/'>Getting Started</a></li>
          <li><a href='http://blog.intertwinkles.org'>Blog</a></li>
          <li><a href='http://twitter.com/intertwinkles'>Follow us on twitter</a></li>
          <li><a href='/about/changelog/'>Change log</a></li>
          <li style='margin-left: -0.5em; font-size: smaller;'>Legal:</li>
          <li><a href='/about/terms/'>Terms of Use</a></li>
          <li><a href='/about/privacy/'>Privacy Policy</a></li>
          <li><a href='/about/dmca/'>DMCA</a></li>
        </ul>
      </div>
      <div class='span4 community'>
        <h2>Community</h2>
        <ul>
          <li><a href='/feedback/'>Feedback and Support</a></li>
          <li><a href='http://lists.byconsens.us/mailman/listinfo/design'>Codesign mailing list</a></li>
          <li><a href='http://project.intertwinkles.org/'>Project tracker</a></li>
          <li><a href='#{INTERTWINKLES_APPS.www.url}/about/related/'>Related projects</a></li>
          <li><a href='http://github.com/yourcelf/intertwinkles/'>Source Code</a><small>: Run your own!</small></li>
        </ul>
      </div>
      <div class='span4 sponsors'>
        <h2>Supported by</h2>
        <a href='http://civic.mit.edu'>
          <img alt='The MIT Center for Civic Media' src='/static/img/C4CM.png'>
        </a>

        <a href='http://voqal.org'>
          <img alt='Voqal' src='/static/img/voqal_logo.svg' />
        </a>

        <a href='http://media.mit.edu/speech'>
          <img alt='The Speech + Mobility Group' src='/static/img/S_M.png'>
        </a>
      </div>
    </div>
  </div>
</div>
<a class='expander' href='#' aria-hidden='true' title='Show footer'>Show bottom links</a>
<a class='collapser' href='#' aria-hidden='true' title='Hide footer'>&ldquo; hide this</a>
""")

class intertwinkles.Footer extends Backbone.View
  template: footer_template
  events:
    'click .collapser':  'collapse'
    'click .expander':    'expand'

  initialize: (options={}) ->
    @collapsed = not not options.collapsed

  render: =>
    @$el.html(@template({collapsed: @collapsed}))
    intertwinkles.twunklify(@$el)
    $("footer, #push, #page").toggleClass("footer-collapsed", @collapsed)
    this

  collapse: (event) =>
    event.preventDefault()
    $("footer, #push, #page").addClass("footer-collapsed")
    $(window).resize()

  expand: (event) =>
    event.preventDefault()
    $("footer, #push, #page").removeClass("footer-collapsed")
    @el.scrollIntoView()
    $(window).resize()



intertwinkles.build_footer = (destination, options) ->
  footer = new intertwinkles.Footer(options)
  footer.render()
  $(destination).html(footer.el)
  return footer

#
# User choice widget
#

user_choice_template = _.template("""
  <input type='text' name='name' id='id_user' data-provide='typeahead' autocomplete='off' value='<%- name %>' />
  <span class='icon-holder' style='width: 32px; display: inline-block;'>
    <% if (icon) { %><img src='<%- icon %>' /><% } %>
  </span>
  <input type='hidden' name='user_id' id='id_user_id' value='<%- user_id %>' />
  <div class='form-hint unknown'></div>
""")

class intertwinkles.UserChoice extends Backbone.View
  tagName: "span"
  template: user_choice_template
  events:
    'keydown input': 'onkey'

  initialize: (options={}) ->
    @model = options.model or {}
    @listenTo intertwinkles.user, "change", @render

  set: (user_id, name) =>
    @model = { user_id: user_id, name: name }
    @$("#user_id").val(name)
    @$("#id_user_id").val(user_id)
    @render()

  render: =>
    user_id = @model.get?("user_id") or @model.user_id
    if user_id and intertwinkles.users?[user_id]?
      name = intertwinkles.users[user_id].name
      icon = intertwinkles.users[user_id].icon
    else
      user_id = ""
      name = @model.get?("name") or @model.name or ""
      icon = {}

    @$el.html(@template({
      name: name
      user_id: user_id
      icon: if icon.small? then icon.small else ""
    }))

    @$("#id_user").typeahead {
      source: @source
      matcher: @matcher
      sorter: @sorter
      updater: @updater
      highlighter: @highlighter
    }
    this

  onkey: (event) =>
    if @$("#id_user").val() != @model.get?("name") or @model.name
      @$(".icon-holder").html("")
      @$("#id_user_id").val("")
      if intertwinkles.is_authenticated()
        @$(".unknown").html("Not a known group member.")
      else
        @$(".unknown").html("
          Sign in first to see your groups. &#8599;
        ")

  source: (query) ->
    return ("#{id}" for id,u of intertwinkles.users)

  matcher: (item) ->
    name = intertwinkles.users[item]?.name
    return name and name.toLowerCase().indexOf(@query.toLowerCase()) != -1

  sorter: (items) ->
    return _.sortBy items, (a) -> intertwinkles.users[a].name

  updater: (item) =>
    @$("#id_user_id").val(item)
    @$(".unknown").html("")
    user = intertwinkles.users[item]
    @model = user
    if user.icon?
      @$(".icon-holder").html("<img src='#{user.icon.small}' />")
    else
      @$(".icon-holder").html("")
    return intertwinkles.users[item].name

  highlighter: (item) ->
    user = intertwinkles.users[item]
    if user.icon?.small?
      img = "<img src='#{user.icon.small}' />"
    else
      img = "<span style='width: 32px; display: inline-block;'></span>"
    query = this.query.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')
    highlit = user.name.replace new RegExp('(' + query + ')', 'ig'), ($1, match) ->
      return '<strong>' + match + '</strong>'
    return "<span>#{img} #{highlit}</span>"

#
# Group choice widget
#

group_choice_template = _.template("""
  <% if (intertwinkles.is_authenticated()) { %>
    <% var has_group = _.keys(intertwinkles.groups).length > 0; %>
    <% if (has_group) { %>
      <select id='id_group'>
        <option value=''>----</option>
        <% for (var key in intertwinkles.groups) { %>
          <% group = intertwinkles.groups[key]; %>
          <option value='<%- group.id %>'><%- group.name %></option>
        <% } %>
      </select>
    <% } else { %>
      <input type='hidden' id='id_group' />
      You don't have any groups yet.
    <% } %>
    <br />
    (<%- has_group ? "or " : "" %><a href='<%- INTERTWINKLES_APPS.www.url %>/groups/new/'>create a new group</a>)
  <% } else { %>
    Sign in to add a group.
  <% } %>
""")

class intertwinkles.GroupChoice extends Backbone.View
  tagName: "span"
  template: group_choice_template
  initialize: (options={}) ->
  render: =>
    @$el.html(@template())
    this

intertwinkles.get_short_url = (params, callback) ->
  socket_callback = "short_url_#{Math.random()}"
  intertwinkles.socket.once socket_callback, (data) ->
    if data.error?
      callback(data.error, null)
    else
      callback(null, data.short_url)
  intertwinkles.socket.send "get_short_url", {
    callback: socket_callback, application: params.application, path: params.path
  }

document_list_template = _.template("""
  <% _.each(docs, function(doc, i) { %>
    <% var dr = deletion_requests[doc.entity]; %>
    <li class='document<%- dr ? " deletion" : "" %>'>
      <a class='document-app-icon hover-show' href='<%- doc.absolute_url %>'>
        <img src='<%- INTERTWINKLES_APPS[doc.application].image %>' alt='<%- doc.application %>' />
        <% if (doc.trash) { %>
          <span class='label'>in trash</span>
        <% } %>
      </a>
      <span class='title'>
        <% if (dr) { %>
          <a class='deletion-request' href='<%- dr.url %>'>
            <span class='label label-important'>Scheduled for deletion <%- intertwinkles.simple_date(dr.end_date, true) %>. <u>manage</u></span>
          </a>
        <% } %>
        <a href='<%- doc.absolute_url %>' class='hover-show' style='display: block;'>
          <%- doc.title %>
        </a>
      </span>
      <span class='date doc-date'><%= intertwinkles.simple_date(doc.modified) %></span>
      <% if (doc.trash) { %>
          <a class='untrash-document' href='#' data-doc-index='<%- i %>'
             title='Restore item from trash'>restore</a>
          &nbsp;
          <% if (dr) { %>
            <a href='<%- dr.url %>'>delete</a>
          <% } else { %>
            <a class='delete-document' href='#' data-doc-index='<%- i %>'>delete</a>
          <% } %>
      <% } else { %>
        <a class='trash-document' title='trash' href='#' data-doc-index='<%- i %>'>
          <i class='icon-trash'></i>
        </a>
      <% } %>
    </li>
  <% }); %>
""")

class intertwinkles.DocumentList extends Backbone.View
  tagName: "ul"
  template: document_list_template
  events: {
    'click .trash-document': 'showTrashDialog'
    'click .untrash-document': 'untrashDocument'
    'click .delete-document': 'showTrashDialog'
    'mouseover .hover-show': 'hoverShowOn'
    'mouseout .hover-show': 'hoverShowOff'
  }

  initialize: (options) ->
    @docs = options.docs
    @deletion_requests = {}
    for dr in options.deletion_requests or []
      @deletion_requests[dr.entity] = dr

  render: =>
    @$el.html(@template({
      docs: @docs
      deletion_requests: @deletion_requests
    }))
    @$el.addClass("documents-list")
    this

  untrashDocument: (event) =>
    doc = @docs[parseInt($(event.currentTarget).attr("data-doc-index"))]
    intertwinkles.socket.once "untrashed", (data) =>
      flash "success", "Item restored from trash."
      @docs = _.reject(@docs, (d) -> d._id == doc._id)
      @render()
    intertwinkles.socket.send "trash_entity", {
      callback: "untrashed"
      application: doc.application
      entity: doc.entity
      title: doc.title
      group: doc.sharing?.group_id
      trash: false
    }

  showTrashDialog: (event) =>
    event.preventDefault()
    doc = @docs[parseInt($(event.currentTarget).attr("data-doc-index"))]
    diag = new intertwinkles.TrashDocumentDialog({doc: doc})
    diag.on "removal", (doc) =>
      @docs = _.reject(@docs, (d) -> d._id == doc._id)
      @render()

  hoverShowOn: (event) =>
    $(event.currentTarget).closest("li").addClass("hovered")
  hoverShowOff: (event) =>
    $(event.currentTarget).closest("li").removeClass("hovered")

trash_document_dialog_template = _.template("""
  <div class='modal-body'>
    <button class='close' type='button' data-dismiss='modal' aria-hidden='true'>&times;</button>
    <% if (can_delete) { %>
      <h3><%- doc.trash ? "Delete" : "Remove" %> item?</h3>
      <div class='well'>
        <img src='<%- INTERTWINKLES_APPS[doc.application].image %>' alt='<%- doc.application %>' style='width: 16px; height: 16px;' />
        <%- doc.title %>
        <span class='date'><%= intertwinkles.simple_date(doc.modified) %></span>
      </div>
      <% if (!doc.trash) { %>
        <p> You have two options. </p>
      <% } %>
    <% } %>
    <div class='row-fluid'>
      <div class='<%- doc.trash ? "" : "span6" %>'>
        <% if (can_delete == "delete") { %>
          <p><%- doc.trash ? "" : "1." %> Delete this permanently right now. (Since others haven't worked on this yet, it doesn't require confirmation). <em>Once deleted, it's gone forever.</em></p>
        <% } else if (can_delete == "queue") { %>
          <p><%- doc.trash ? "" : "1." %> Request that this item be deleted permanently. Others in your group will be notified, and have <b>three days</b> in which to contest or confirm deletion.  If any <b>one</b> person confirms, it will be deleted right then. If anyone contests, it won't be deleted.  If three days pass without input, it'll be deleted. <em>Once deleted, it's gone forever.</em></p>
        <% } %>
      </div>
      <% if (!doc.trash) { %>
        <div class='span6'>
          <p><%= can_delete ? "2." : "" %> Move this item to the trash. This can be undone, and the content remains on InterTwinkles.</p>
        </div>
      <% } %>
    </div>
  </div>
  <div class='modal-footer'>
    <% if (can_delete) { %>
      <button class='pull-left btn btn-large btn-danger request-deletion'>
        <% if (can_delete == "delete") { %>
          Delete right now
        <% } else if (can_delete == "queue") { %>
          Request deletion
        <% } %>
      </button>
    <% } %>
    <% if (!doc.trash) { %>
      <button class='btn btn-large btn-primary trash-entity'>Move to trash (archive)</button>
    <% } else { %>
      <a class='close btn' data-dismiss='modal' href='#'>Cancel</a>
    <% } %>
  </div>
""")

class intertwinkles.TrashDocumentDialog extends intertwinkles.BaseModalFormView
  template: trash_document_dialog_template
  events:
    'click .trash-entity': 'trashEntity'
    'click .request-deletion': 'requestDeletion'

  initialize: (options) ->
    @doc = options.doc
    intertwinkles.socket.once "can_delete", (data) =>
      super {
        context: {doc: @doc, can_delete: data.can_delete}
      }
      @render()
    intertwinkles.socket.send "check_deletable", {
      callback: "can_delete"
      application: @doc.application
      entity: @doc.entity
      title: @doc.title
      url: @doc.url
      group: @doc.sharing?.group_id
    }

  trashEntity: (event) =>
    event.preventDefault()
    intertwinkles.socket.once "trashed", (data) =>
      flash "success", "Item moved to the trash."
      @trigger "removal", @doc
      @remove()
    intertwinkles.socket.send "trash_entity", {
      callback: "trashed"
      application: @doc.application
      entity: @doc.entity
      title: @doc.title
      url: @doc.url
      group: @doc.sharing?.group_id
      trash: true
    }

  requestDeletion: (event) =>
    event.preventDefault()
    intertwinkles.socket.once "trashed", (data) =>
      if data.deletion_request
        flash("success", "Item scheduled for deletion on " + intertwinkles.simple_date(data.deletion_request.end_date, true))
      else
        flash("success", "Item deleted, and is gone forever.")
      @trigger "removal", @doc
      @remove()
    intertwinkles.socket.send "request_deletion", {
      callback: "trashed"
      application: @doc.application
      entity: @doc.entity
      title: @doc.title
      url: @doc.url
      group: @doc.sharing?.group_id
    }
