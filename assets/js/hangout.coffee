class HangoutDocument extends Backbone.Model
class HangoutDocumentList extends Backbone.Collection
  model: HangoutDocument

class intertwinkles.Hangout extends Backbone.View
  initialize: (options) ->
    window.INTERTWINKLES_AUTH_LOGOUT_REDIRECT = "/hangout/"
    @hangout_docs = new HangoutDocumentList()
    window.addEventListener "message", @message_listener, false
    window.parent.postMessage({
      get: "getHangoutUrl"
    }, INITIAL_DATA.hangout_origin)
    @listenTo intertwinkles.socket, "hangout:document_list", @load

  load: (data) =>
    console.info "Got new hangout docs:", data.hangout_docs
    for doc in data.hangout_docs
      existing = @hangout_docs.findWhere({absolute_url: doc.absolute_url})
      if existing
        existing.clear()
        existing.set(doc)
      else
        @hangout_docs.add(new HangoutDocument(doc))
    if @hangout_docs.length > 0 and not @current_url
      @setDocument(@hangout_docs.at(@hangout_docs.length - 1).get("absolute_url"))
      
  fetchHangoutDocuments: =>
    if @room_name
      intertwinkles.socket.send "hangout/list_room_documents", {room: @room_name}

  remove: =>
    super()
    window.removeEventListener "message", @message_listener, false
      
  message_listener: (event) =>
    if event.origin == INITIAL_DATA.hangout_origin
      if event.data.hangoutUrl
        console.info "Setting hangout url:", event.data.hangoutUrl
        @join(event.data.hangoutUrl)

  join: (hangout_url) =>
    # TODO: join an intertwinkles socket room for this hangout, get list of
    # any current documents in play.
    @room_name = "hangout/" + encodeURIComponent(hangout_url)
    @room_view?.remove()
    @room_view = new intertwinkles.RoomUsersMenu({room: @room_name})
  
  render: =>
    @main = new HangoutMain({hangout_docs: @hangout_docs})
    $("#app").append(@main.el)
    @main.render()
      
    @sidebar = new HangoutSidebar({hangout_docs: @hangout_docs})
    $("#app").append(@sidebar.el)
    @sidebar.render()

    @documentAdder = new HangoutDocumentAdderView({hangout_docs: @hangout_docs})
    $("#app").append(@documentAdder.el)
    @documentAdder.render()

    @sidebar.on "openDocumentChooser", @documentAdder.reveal
    @sidebar.on "setDocument", @setDocument
    @documentAdder.on "addDocument", @setDocument
    @documentAdder.on "fetchHangoutDocuments", @fetchHangoutDocuments

    if @current_url
      @setDocument(@current_url)

  setDocument: (url) =>
    @documentAdder.hide()
    if @hangout_docs.findWhere({absolute_url: url})
      @current_url = url
      @sidebar.setDocument(url)
      @main.setDocument(url)
    else
      intertwinkles.socket.send "hangout/add_document", {request_url: url, room: @room_name}
      intertwinkles.socket.once "hangout:document_list", (data) =>
        if @hangout_docs.findWhere({absolute_url: url})?
          @setDocument(url)
        else
          flash "error", "Error setting document"

hangout_sidebar_template = """
  <div class='navbar navbar-inverse reveal-sidebar'>
    <span class='title'>
      Inter<span class='intertwinkles'>Twinkles</span>
    </span>
    <button class='btn btn-navbar' type='button'>
      <span class='icon-bar'></span>
      <span class='icon-bar'></span>
      <span class='icon-bar'></span>
    </button>
    <div style='clear: both;'></div>
  </div>
  <ul class='document-list'>
    <% for (var i = hangout_docs.length - 1; i >= 0; i--) { %>
      <% var doc = hangout_docs.at(i); %>
      <li data-url='<%- encodeURIComponent(doc.get('absolute_url')) %>'
          class='hangout-doc'>
        <% if (doc.get('application')) { %>
          <img src='<%- INTERTWINKLES_APPS[doc.get('application')].image %>'
               alt='<%- doc.get('application') %>'
               class='app-tile' />
          <span class='title'><%- doc.get('title') %></span>
        <% } else { %>
          <span class='icon-question-sign'></span>
          <span class='title'><em>Permission problem</em></span>
        <% } %>
      </li>
    <% } %>
  </ul>
  <button class='btn btn-small add-document'>
    <span class='icon-plus'></span>
    <span class='title'>Add activity</span>
  </button>
"""
class HangoutSidebar extends Backbone.View
  template: _.template(hangout_sidebar_template)
  events:
    'click .reveal-sidebar': '_toggleSidebar'
    'click .add-document': '_openDocumentChooser'
    'click .hangout-doc': '_setDocument'
    'click': '_toggleSidebar'

  initialize: (options) ->
    @hangout_docs = options.hangout_docs
    @listenTo @hangout_docs, "change add remove", @render

  render: =>
    @$el.addClass('hangout-sidebar')
    @$el.html(@template({
      hangout_docs: @hangout_docs
    }))
    intertwinkles.twunklify(@el)
    this

  setDocument: (url) =>
    @$("li").removeClass("active")
    @$("li[data-url='#{encodeURIComponent(url)}']").addClass("active")
    @hide()

  _setDocument: (event) =>
    event.stopPropagation()
    url = decodeURIComponent($(event.currentTarget).attr("data-url"))
    @trigger "setDocument", url

  reveal: =>
    @$el.addClass("expanded")

  hide: =>
    @$el.removeClass("expanded")
 
  _toggleSidebar: (event) =>
    event.stopPropagation()
    @$el.toggleClass("expanded")

  _openDocumentChooser: (event) =>
    event.stopPropagation()
    @trigger "openDocumentChooser"

hangout_document_chooser_template = """
  <form class='form-horizontal'>
    <div class='main'>
      <div class='document-list-holder'>
        <% if (intertwinkles.is_authenticated()) { %>
            <img src='/static/img/spinner.gif' alt='Loading'>
        <% } else { %>
          <div class='alert alert-warning' style='text-align: center;'>
            <a class='sign-in' href='#'>Sign in</a> to InterTwinkles see your groups' documents.
          </div>
        <% } %>
      </div>
    </div>
    <div class='head'>
      <a class='btn close cancel'>&larr; back</a>
      <h3>Choose activity</h3>
      <div style='clear: both;'></div>
    </div>
    <div class='foot'>
      <div class='control-group'>
        <label class='control-label'>URL</label>
        <div class='controls'>
          <div><em>(Or paste an InterTwinkles URL):</em></div>
          <input name='custom-url' type='text' placeholder='<%= window.location.origin %>/...'/>
          <input type='submit' class='btn btn-primary disabled' value='Add to hangout' />
        </div>
      </div>
    </div>
  </form>
"""

class HangoutDocumentAdderView extends Backbone.View
  template: _.template(hangout_document_chooser_template)
  events:
    'click .cancel':  'hide'
    'click .sign-in': 'signIn'
    'submit form':    'chooseDoc'
    'keyup input[name=custom-url]': '_customUrlKey'

  initialize: (options) ->
    @hangout_docs = options.hangout_docs
    @user_docs = null

    @listenTo intertwinkles.user, "login", =>
      @fetchUserDocuments()
      @trigger "fetchHangoutDocuments"
      @render()

  signIn: =>
    intertwinkles.request_login("/hangout/")

  chooseDoc: (event) =>
    event?.preventDefault()
    return if @$("input[type=submit]").hasClass("disabled")
    val = @$("input[name=custom-url]").val()
    @trigger "addDocument", val

  fetchUserDocuments: =>
    intertwinkles.socket.once "hangout:user_documents", (data) =>
      @user_docs = data.docs
      @renderDocumentList()
    intertwinkles.socket.send("hangout/list_user_documents")

  render: =>
    @$el.addClass("hangout-document-chooser")
    @$el.html(@template({
      hangout_docs: @hangout_docs
      user_docs: @user_docs
    }))
    @renderDocumentList()

  renderDocumentList: =>
    @document_list?.remove()
    if @user_docs != null
      @document_list = new HangoutDocumentListView({docs: @user_docs})
      @$(".document-list-holder").html(@document_list.el)
      @document_list.render()
      @document_list.on "selectDocument", (href) =>
        @$("input[name=custom-url]").val(href)
        @setSubmitEnable(@chooseDoc)

  reveal: =>
    if intertwinkles.is_authenticated()
      @fetchUserDocuments()
    @$el.css("display", "block")

  hide: =>
    @$el.css("display", "none")

  _customUrlKey: (event) =>
    @setSubmitEnable()

  setSubmitEnable: (callback) =>
    val = @$("input[name=custom-url]").val()
    @$("input[type=submit]").addClass("loading")
    if val
      intertwinkles.socket.once "hangout:validate_url", (data) =>
        @$("input[type=submit]").removeClass("loading")
        @$("input[name=custom-url]").val(data.normalized or data.request_url)
        @$("input[type=submit]").toggleClass("disabled", not (data.valid == true))
        callback?()

      intertwinkles.socket.send "hangout/validate_url", {request_url: val}
    else
      @$("input[type=submit]").addClass("disabled")
    

class HangoutDocumentListView extends intertwinkles.DocumentList
  events: {
    # Do not include "trash/delete" events from parent
    'mouseover .hover-show': 'hoverShowOn'
    'mouseout .hover-show': 'hoverShowOff'
    'click a': 'selectDocument'
  }
  showTrashDialog: (event) => event.preventDefault()
  untrashDocument: (event) => event.preventDefault()
  selectDocument:  (event) =>
    event.preventDefault()
    @trigger "selectDocument", $(event.currentTarget).attr("href")

hangout_main_template = """
<% if (url) { %>
  <iframe class='activity' src='<%- url %>' width='100%' height='100%' />
<% } else { %>
  <div class='placeholder'>
    <img src='/static/img/logo-220x140.png' 
         alt='InterTwinkles' />
  </div>
<% } %>
"""

class HangoutMain extends Backbone.View
  template: _.template(hangout_main_template)

  render: =>
    @$el.addClass("hangout-main")
    @$el.html(@template({url: @url}))

  setDocument: (url) =>
    @url = url
    @render()


