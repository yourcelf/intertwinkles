class GroupDocumentList extends Backbone.View
  template: _.template $("#groupsList").html()
  groupDocListTemplate: _.template $("#groupDocumentList").html()
  emptyGroupDocListTemplate: _.template $("#emptyGroup").html()

  initialize: ->
    # Organize events by group
    _eventsByGroup = {}
    _personalEvents = []
    for event in INITIAL_DATA.events
      if intertwinkles.groups[event.group]?
        _eventsByGroup[event.group] ?= []
        _eventsByGroup[event.group].push(event)
      else
        _personalEvents.push(event)
    @groupEvents = {}
    for group_id, events of _eventsByGroup
      @groupEvents[group_id] = intertwinkles.buildEventCollection(events)
    @personalEvents = intertwinkles.buildEventCollection(_personalEvents)

    # Organize documents by group and date
    @groupDocs = []
    @emptyGroups = []
    for {group_id, docs} in INITIAL_DATA.groups_docs
      group = intertwinkles.groups[group_id]
      if docs.length > 0
        @groupDocs.push({ group, docs })
        for doc in docs
          doc.modified = intertwinkles.parse_date(doc.modified)
      else
        @emptyGroups.push(group)

    @groupDocs = _.sortBy(@groupDocs, (g) -> -g.docs[0].modified.getTime())

  render: =>
    @$el.html(@template())
    for struct in @groupDocs
      item = $(@groupDocListTemplate({group: struct.group, docs: struct.docs}))
      @$(".groups").append(item)
      $(".events-pane", item).html(new intertwinkles.RecentEventsSummary({
        collection: @groupEvents[struct.group._id]
      }).render().el)
      $(".documents-list", item).replaceWith(new intertwinkles.DocumentList({
        docs: struct.docs
      }).render().el)
    for group in @emptyGroups
      @$(".groups").append(@emptyGroupDocListTemplate({group}))
    this

dash_app_list_template = _.template($("#appList").html())

intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "www"})
  intertwinkles.build_footer($("footer"))
  list = new GroupDocumentList()
  $("#dashboard").html(list.el)
  list.render()
  $(".dash-app-list-holder").html(dash_app_list_template( {
    apps: (app for label,app of INTERTWINKLES_APPS when label != "www")
  }))

