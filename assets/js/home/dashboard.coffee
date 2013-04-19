class GroupDocumentList extends Backbone.View
  template: _.template($("#groupsList").html())
  itemTemplate: _.template($("#groupDocumentList").html())

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
    for docs in INITIAL_DATA.groups_docs
      if docs.length > 0
        group =  intertwinkles.groups[docs[0].sharing.group_id]
        @groupDocs.push({ group, docs })
        for doc in docs
          doc.modified = intertwinkles.parse_date(doc.modified)


    @groupDocs = _.sortBy(@groupDocs, (g) -> -g.docs[0].modified.getTime())

  render: =>
    @$el.html(@template())
    for struct in @groupDocs
      item = $(@itemTemplate({group: struct.group, docs: struct.docs}))
      @$(".groups").append(item)
      $(".events-pane", item).html(new intertwinkles.RecentEventsSummary({
        collection: @groupEvents[struct.group._id]
      }).render().el)
      $(".documents-list", item).replaceWith(new intertwinkles.DocumentList({
        docs: struct.docs
      }).render().el)
    this

intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "www"})
  intertwinkles.build_footer($("footer"))
  list = new GroupDocumentList()
  $("#dashboard").html(list.el)
  list.render()



