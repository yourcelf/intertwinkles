#= require ../vendor/d3.v3.js

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
  comparator: (r) -> return -intertwinkles.parse_date(r.get("date")).getTime()

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
      attrsA.type == attrsB.type == "visit" and #XXX only dedupe visits??
      attrsA.entity == attrsB.entity and
      attrsA.user == attrsB.user and
      attrsA.via_user == attrsB.via_user and
      attrsA.group == attrsB.group and
      attrsA.manner == attrsB.manner and
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

intertwinkles.buildEventCollection = (events) ->
  collection = new intertwinkles.EventCollection()
  for event in events
    event.date = intertwinkles.parse_date(event.date)
  collection.add(new intertwinkles.Event(event) for event in events)
  return collection


events_summary_template = """
  <div class='events-summary'>
    <div class='counts'>
      <%- stats.numVisits %> visits,
      <%- stats.numEdits %> edits over
      <%- days %> day<%- days == 1 ? "" : "s" %>.
      <span class='more'>
        <a href='#' class='history'>details</a>
      </span>
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
    this

  showHistory: (event) =>
    event.preventDefault()
    event.stopPropagation()
    new intertwinkles.EventsHistory({collection: @coll}).render()

recent_events_summary_template = """
  <div class='recent-activity-summary'>
    <div class='counts'>
      <%- stats.numVisits %> visits,
      <%- stats.numEdits %> edits
      <%- days <= 1 ? "since yesterday" : "over the last " + day + " days" %>
      <a href='#' class='history'>details</a>
    </div>
    <div class='current'>
      <% if (stats.editors.length > 0) { %>
        Recent editors:
        <% for (var i = 0; i < Math.min(stats.editors.length, 5); i++) { %>
          <% var ident = stats.editors[i]; %>
          <%= intertwinkles.user_icon(ident.user, ident.name, "tiny") %>
        <% } %>
      <% } %>
    </div>
  </div>
"""
class intertwinkles.RecentEventsSummary extends Backbone.View
  template: _.template(recent_events_summary_template)
  events: {
    'click .recent-activity-summary': 'showHistory'
    'click .history':                 'showHistory'
  }
  initialize: (options) ->
    @coll = options.collection
    @groupCount = intertwinkles.groups[@coll.at(0)?.get("group")]?.members.length

  render: =>
    if @coll.length > 0
      stats = @coll.summarize()
      days = Math.ceil(
        (new Date().getTime() - stats.start.getTime()) / (1000 * 60 * 60 * 24)
      )
      @$el.html(@template({stats: stats, days: days}))
    this
    
  showHistory: (event) =>
    event.preventDefault()
    event.stopPropagation()
    new intertwinkles.RecentEventsHistory({collection: @coll}).render()


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
  <div class='modal-footer'>
    <a data-dismiss='modal' class='btn'>Close</a>
  </div>
"""
class intertwinkles.EventsHistory extends intertwinkles.BaseModalFormView
  template: _.template(event_history_template)
  initialize: (options) ->
    @context = { events: options.collection }

#
# Recent events history show things across multiple documents, grouped by
# document.
#
recent_events_history_template = """
  <div class='modal-body'>
    <button class='close' type='button' data-dismiss='modal' title='close'>&times;</button>
    <h3>Recent activity</h3>
    <div class='recent-activity'>
      <% _.each(entities, function (events) { %>
        <% var event = events.at(0); %>
        <div class='entity <%- events.length > 10 ? 'longer collapsed' : '' %>'>
          <div class='event-list'>
            <span class='entity-name document-app-icon'>
              <a href='<%- event.get("absolute_url") %>'>
                <img src='<%- INTERTWINKLES_APPS[event.get("application")].image %>' alt='<%- event.get("application") %>' />
              </a>
              <a href='<%- event.get("absolute_url") %>'><%- event.get("grammar")[0].entity %></a>
            </span>
            <% events.each(function(event) { %>
              <% var grammar = event.get("grammar"); %>
              <span class='event <%- event.get("type") %>'>
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
              </span>
            <% }); %>
            <div class='fadeout'></div>
          </div>
          <% if (events.length > 10) { %>
            <a href='#' class='more'>show more</a>
          <% } %>
        </div>
      <% }); %>
    </div>
  </div>
  <div class='modal-footer'>
    <a data-dismiss='modal' class='btn'>Close</a>
  </div>
"""
class intertwinkles.RecentEventsHistory extends intertwinkles.BaseModalFormView
  template: _.template(recent_events_history_template)
  events:
    'click .more': 'showMore'
  initialize: (options) ->
    # Then partition by entity...
    by_entity = {}
    entity_order = []
    options.collection.each (event) ->
      entity = event.get("entity")
      if not by_entity[entity]?
        by_entity[entity] = new intertwinkles.EventCollection()
        entity_order.push(entity)
      by_entity[entity].add(event)

    @context = {
      entities:  (by_entity[entity].deduplicate() for entity in entity_order)
    }

  showMore: (event) =>
    event.preventDefault()
    link = $(event.currentTarget)
    container = link.closest(".entity.longer")
    container.toggleClass("collapsed")
    if container.hasClass("collapsed")
      link.html("show more")
    else
      link.html("show fewer")
