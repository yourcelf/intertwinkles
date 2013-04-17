#= require ../vendor/d3.v3.js

intertwinkles.build_timeline = (selector, collection, formatter) ->
  timeline = new TimelineView({ collection: collection, formatter: formatter })
  $(selector).html(timeline.el)
  timeline.render()
  return timeline

class intertwinkles.Event extends Backbone.Model
  # Return an object containing one of:
  #   'user': a user id
  #   'name': a name for a non-authenticated but self-identified user
  #   'anon_id': an id for a non-authenticated, non-self-identified user
  getIdent: =>
    if @get('user')
      return {user: @get('user')}
    if @get('data')?.user?.name
      return {name: @get('data')?.user?.name}
    return {anon_id: @get('anon_id')}

class intertwinkles.EventCollection extends Backbone.Collection
  model: Event
  comparator: (r) -> return intertwinkles.parse_date(r.get("date")).getTime()

  # Return a new collection which contains only those events which are not
  # duplicates (e.g. repeat visits) within the given timespan.
  #TODO
  deduplicate: (timespan=1000*60*6) =>
    deduped = new intertwinkles.EventCollection()
    _lastEventByUser = {}
    @each (event) =>
      ident = event.getIdent()
      key = ident.user or ident.name or ident.anon_id
      if _lastEventByUser[key] and @resembles(_lastEventByUser[key], event)
        _lastEventByUser[key] = event
      else
        if _lastEventByUser[key]
          deduped.add(_lastEventByUser[key])
        _lastEventByUser[key] = event
    for key, event of _lastEventByUser
      deduped.add(event)
    return deduped

  resembles: (eventA, eventB) ->
    attrsA = eventA.attributes
    attrsB = eventB.attributes
    return (
      attrsA.application == attrsB.application and
      attrsA.type == attrsB.type and
      attrsA.entity == attrsB.entity and
      attrsA.user == attrsB.user and
      attrsA.via_user == attrsB.via_user and
      attrsA.group == attrsB.group and
      attrsA.data?.user?.name == attrsB.data?.user?.name and
      _.isEqual(_.keys(attrsA.data or {}), _.keys(attrsB.data or {})) and
      Math.abs(attrsA.date.getTime() - attrsB.date.getTime()) < (1000 * 60 * 60 * 6)
    )

  # Given a list of event types that should not count as modifications, return
  # a structure summarizing details of the visitors, editors, and list of people
  # who are 'current' (have seen this since the last edit).
  summarize: (modificationWhitelist=["visit", "vote"]) =>
    out = {
      numVisits: 0      # Total number of non-duplicate events.
      numEdits: 0       # Total number of non-duplicate modifying events.
      visitors: []      # List of unique authenticated visitors.
      anonVisitors: []  # List of unique anonymous visitors.
      editors: []       # List of all editors.
      current: []       # List of unique authenticated visitors since the last edit.
      lastEdit: null    # Event model referring to most recent edit
    }
    # Build a hash of the modification whitelist for easy testing of inclusion.
    _modWhitelist = {}
    for type in modificationWhitelist
      _modWhitelist[type] = true

    # Loop through backwards, so we get newest events first.
    for i in [@models.length-1..0]
      event = @at(i)
      out.numVisits += 1

      # Add visitors
      ident = event.getIdent()
      if ident.anon_id?
        out.anonVisitors.push(ident)
      else
        out.visitors.push(ident)

      # Add current.
      if not out.lastEdit and ident.user
        group = intertwinkles.groups[event.get("group")]
        if group? and _.find(group.members, (u) -> u.user == ident.user)
          out.current.push(ident)
          if event.get("via_user")
            out.current.push({user: event.get("via_user")})

      # Add editors
      if not _modWhitelist[event.get("type")]
        if not out.lastEdit
          out.lastEdit = event
        out.editors.push(ident)
        out.numEdits += 1

    if intertwinkles.is_authenticated()
      out.current.push({
        user: intertwinkles.user.id
        name: intertwinkles.user.get("name")
      })

    # Assume that names, user id's, and anon id's will never collide.
    _key = (ident) -> ident.user or ident.name or ident.anon_id
    out.visitors = _.uniq(out.visitors, false, _key)
    out.anonVisitors = _.unique(out.anonVisitors, false, _key)
    out.editors = _.uniq(out.editors, false, _key)
    out.current = _.uniq(out.current, false, _key)
    out.start = @at(0)?.get("date") or new Date()
    return out

intertwinkles.buildEventCollection = (data) ->
  collection = new intertwinkles.EventCollection()
  for event in data.events
    event.date = intertwinkles.parse_date(event.date)
  collection.add(new intertwinkles.Event(event) for event in data.events)
  return collection


events_summary_template = """
  <div class='events-summary'>
    <h4>History</h4>
    <div class='counts'>
      <%- stats.numVisits %> visits,
      <%- stats.numEdits %> edits over
      <%- days %> day<%- days == 1 ? "" : "s" %>.
    </div>
    <div class='current'>
      <% if (stats.current.length > 0) { %>
        <% if (groupCount) { %>
          <%- stats.current.length %>/<%- groupCount %> group members are up to date:
        <% } else {%>
          Up to date:
        <% } %>
        <% _.each(stats.current, function(ident) { %>
          <%= intertwinkles.user_icon(ident.user, ident.name, "tiny") %>
        <% }); %>
      <% } %>
    </div>
    <div class='more'>
      <a href='#' class='history'>more</a>
    </div>
  </div>
"""

class intertwinkles.EventsSummary extends Backbone.View
  template: _.template(events_summary_template)
  events: {
    'click .events-summary': 'showHistory'
  }
  # All event types are counted as "visits", but not all are counted as
  # "changes". Since one of the important distinctions we're after is "who has
  # seen the latest?", we want to identify those keys that do not count as a
  # "change". If a change event happens, any prior visitors are no longer
  # considered up-to-date.
  modificationWhitelist: ["visit", "vote"]
  # This should be constructed with a collection of events that all refer to a
  # single entity.
  initialize: (options) ->
    @coll = options.collection
    @groupCount = intertwinkles.groups[@coll.at(0)?.get("group")]?.members.length
    if options.modificationWhitelist?
      @modificationWhitelist = options.modificationWhitelist
    
  render: =>
    stats = @coll.summarize(@modificationWhitelist)
    days = 0
    if stats.lastEdit
      days = Math.ceil(
        (new Date().getTime() - stats.start.getTime()) / (1000 * 60 * 60 * 24)
      )
    @$el.html(@template({stats: stats, days: days, groupCount: @groupCount}))

  showHistory: (event) =>
    event.preventDefault()
    event.stopPropagation()
    new intertwinkles.EventsHistory({collection: @coll}).render()

event_history_template = """
  <div class='modal-body'>
    <button class='close' type='button' data-dismiss='modal' title='close'>&times;</button>
    <h3>History</h3>
    <div class='event-history'>
      <div class='event header'>
        <span class='date'>When</span>
        <span class='attrib'>Who</span>
        <span class='about'>What</span>
      </div>
      <% events.each(function(event) { %>
        <% var grammar = event.get("grammar"); %>
        <% var data = event.get("data"); %>
        <% var name = data && data.user ? data.user.name : undefined; %>
        <div class='event <%- event.get("type") %>'>
          <%= intertwinkles.simple_date(event.get("date")) %>
          <span class='attrib'>
            <%= intertwinkles.inline_user(event.get("user"), name) %>
            <% if (event.get("via_user")) { %>
              <span class='via'>
                (via <%= intertwinkles.inline_user(event.get("via_user")) %>)
              </span>
            <% } %>
          </span>
          <span class='about'>
            <% for (var i = 0; i < grammar.length; i++) { %>
              <span class='verbed'><%- grammar[i].verbed %></span>
              <span class='aspect'><%- grammar[i].aspect %></span>
              <% if (grammar[i].manner) { %>
                <span class='manner'>(<%- grammar[i].manner %>)</span>
              <% } %>
              <br />
            <% } %>
          </span>
        </div>
      <% }); %>
    </div>
  </div>
"""
class intertwinkles.EventsHistory extends intertwinkles.BaseModalFormView
  template: _.template(event_history_template)
  initialize: (options) ->
    coll = options.collection.clone()
    coll.comparator = (e) -> -intertwinkles.parse_date(e.get("date")).getTime()
    coll.sort()
    @context = { events: coll }

##############################################
# The old way... a ruled timeline view:
##############################################
#
#ruled_timeline_template = """
#  <div class='container timeline'>
#    <% for (var i = 0; i < rows.length; i++) { %>
#      <div class='row-fluid ruled'>
#        <div class='span2' style='text-align: right;'><%- rows[i].label %></div>
#        <div class='span8' style='position: relative;'>
#          <% for (var j = 0; j < rows[i].length; j++) { %>
#            <% var point = rows[i][j]; %>
#            <span class='timeline-bump' style='left: <%- point.left %>%'>
#              <%= point.formatted %>
#            </span>
#          <% } %>
#        </div>
#      </div>
#    <% } %>
#    <div class='row-fluid'>
#      <div class='span2'></div>
#      <div class='span8 ruled' style='position: relative;'>
#        <% for (var i = 0; i < ticks.length; i++) { %>
#          <span class='date-legend'
#                style='left: <%- ticks[i].left %>%'
#                ><%- ticks[i].label %></span>
#        <% } %>
#      </div>
#  </div>
#"""
#
#class TimelineView extends Backbone.View
#  template:  _.template(ruled_timeline_template)
#
#  initialize: (options) ->
#    @coll = options.collection
#    @formatter = options.formatter
#
#  render: =>
#    if @coll.length == 0
#      @$el.html("")
#      return this
#    rows = []
#    ticks = []
#    min_date = @coll.at(0).get("date")
#    min_time = min_date.getTime()
#    max_date = @coll.at(@coll.length - 1).get("date")
#    max_time = max_date.getTime()
#    time_span = Math.max(max_time - min_time, 1)
#    @coll.each (entry) =>
#      type = entry.get("type")
#      unless rows[type]?
#        rows[type] = []
#        rows[type].label = entry.get("type")
#        rows.push(rows[type])
#      point = {
#        formatted: @formatter(entry.toJSON())
#        left: 100 * (entry.get("date").getTime() - min_time) / time_span
#      }
#      rows[type].push(point)
#
#    # Build timeline scale
#    if time_span < 1000 * 60
#      date_fmt = "h:mm:s"
#      step = 1000
#    else if time_span < 1000 * 60 * 60
#      date_fmt = "h:mm tt"
#      step = 1000 * 60
#    else if time_span < 1000 * 60 * 60 * 24
#      date_fmt = "h tt"
#      step = 1000 * 60 * 60
#    else if time_span < 1000 * 60 * 60 * 24 * 7
#      date_fmt = "ddd M-d"
#      step = 1000 * 60 * 60 * 24
#    else if time_span < 1000 * 60 * 60 * 24 * 14
#      date_fmt = "M-d"
#      step = 1000 * 60 * 60 * 24
#    else if time_span < 1000 * 60 * 60 * 24 * 7 * 12
#      date_fmt = "MMM d"
#      step = 1000 * 60 * 60 * 24 * 31
#    else if time_span < 1000 * 60 * 60 * 24 * 7 * 52
#      date_fmt = "MMM"
#      step = 1000 * 60 * 60 * 24 * 31
#    else
#      date_fmt = "yyyy"
#      step = 1000 * 60 * 60 * 24 * 365
#
#    # Adjust scale. #FIXME
#    while time_span / step < 2
#      step /= 2
#    while time_span / step > 10
#      step *= 2
#
#    ticks = []
#    i = 0
#    while true
#      next = step * i++
#      if next < time_span
#        ticks.push({
#          label: new Date(min_time + next).toString(date_fmt)
#          left: parseInt(next / time_span * 100)
#        })
#      else
#        break
#
#    @$el.html @template({ rows, ticks })
#    @$("[rel=popover]").popover()
#
#
