#= require ../intertwinkles/js/intertwinkles/index

intertwinkles.build_toolbar($("header"), {applabel: "resolve"})
intertwinkles.build_footer($("footer"))

resolve = window.resolve = {}

class Proposal extends Backbone.Model
  idAttribute: "_id"
class ProposalCollection extends Backbone.Collection
  model: Proposal
  comparator: (p) ->
    return new Date(p.get("revisions")[0].date).getTime()

resolve.model = new Proposal()

if INITIAL_DATA.proposal?
  resolve.model.set(INITIAL_DATA.proposal)
if INITIAL_DATA.listed_proposals?
  resolve.listed_proposals = INITIAL_DATA.listed_proposals

handle_error = (data) ->
  flash "error", "Oh golly, but the server has errored. So sorry."
  console.info(data)

class SplashView extends intertwinkles.BaseView
  template: _.template($("#splashTemplate").html())
  itemTemplate: _.template($("#listedProposalTemplate").html())
  events: _.extend {
  }, intertwinkles.BaseEvents
  
  initialize: ->
    intertwinkles.user.on "change", @getProposalList
    super()

  remove: =>
    intertwinkles.user.off "change", @getProposalList
    super()

  render: =>
    @$el.html(@template())

    selector_lists = [
      [@$(".group-proposals"), resolve.listed_proposals?.group]
      [@$(".public-proposals"), resolve.listed_proposals?.public]
    ]

    for [selector, list] in selector_lists
      if list? and list.length > 0
        selector.html("")
        for proposal in list
          listing = @itemTemplate({
            url: "/p/#{proposal._id}/"
            proposal: proposal
            group: intertwinkles.groups?[proposal.sharing?.group_id]
          })
          selector.append(listing)
    @$(".proposal-listing-date").each =>
      @addView this, new intertwinkles.AutoUpdatingDate($(this).attr("data-date"))


  getProposalList: =>
    intertwinkles.socket.on "list_proposals", (data) =>
      if data.error?
        flash "error", "The server. It has got confused."
      else
        resolve.listed_proposals = data.proposals
        @render()
    intertwinkles.socket.emit "get_proposal_list", {
      callback: "list_proposals"
    }

class AddProposalView extends intertwinkles.BaseView
  template: _.template($("#addProposalTemplate").html())
  events: _.extend {
    'submit   form': 'saveProposal'
  }, intertwinkles.BaseEvents

  initialize: ->
    intertwinkles.user.on("change", @onUserChange)
    super()

  remove: =>
    intertwinkles.user.off("change", @onUserChange)
    super()

  onUserChange: =>
    val = @$("textarea").val()
    @render()
    @$("textarea").val(val)

  render: =>
    @$el.html(@template())
    @sharing = new intertwinkles.SharingFormControl()
    @addView(".group-choice", @sharing)

  saveProposal: (event) =>
    event.preventDefault()
    # Validate fields.
    cleaned_data = @validateFields "form", [
      ["#id_proposal", ((val) -> val or null), "This field is required."]
      ["#id_name", (val) ->
        if $("#id_user_id").val() or val
          return val or ""
        return null
      , "Please add a name here, or sign in."]
    ]
    if cleaned_data == false
      return
    
    # Upload form. 
    cleaned_data['sharing'] = @sharing.sharing
    callback = "proposal_saved"

    intertwinkles.socket.once callback, (data) =>
      return handle_error(data) if data.error?
      @$("[type=submit]").removeClass("loading").attr("disabled", false)
      resolve.model.set(data.proposal)
      resolve.app.navigate "/p/#{data.proposal._id}/", trigger: true

    @$("[type=submit]").addClass("loading").attr("disabled", true)
    intertwinkles.socket.emit "save_proposal", {
      callback: callback,
      proposal: cleaned_data
      action: "create"
    }

class ShowProposalView extends intertwinkles.BaseView
  template: _.template($("#showProposalTemplate").html())
  opinionTemplate: _.template($("#opinionTemplate").html())
  talliesTemplate: _.template($("#talliesTemplate").html())
  events: _.extend {
    'click button.edit-proposal': 'showEditProposalForm'
    'click   .finalize-proposal': 'finalizeProposal'
    'click     .proposal-passed': 'proposalPassed'
    'click     .proposal-failed': 'proposalFailed'
    'submit  form.edit-proposal': 'saveProposalRevision'
    'click        .respond-link': 'showOpinionForm'
    'submit       form.weigh-in': 'saveOpinion'
    'click     a.delete-opinion': 'showDeleteOpinionForm'
    'submit form.delete-opinion': 'deleteOpinion'
    'click        .edit-opinion': 'editOpinion'
    'click     .confirm-my-vote': 'confirmMyVote'
    'click     .reopen-proposal': 'showReOpenProposalForm'
    'click       .really-reopen': 'reOpenProposal'
  }, intertwinkles.BaseEvents

  votes: {
    yes: "Strongly approve"
    weak_yes: "Approve with reservations"
    discuss: "Need more discussion"
    no: "Have concerns"
    block: "Block"
    abstain: "I have a conflict of interest"
  }

  initialize: (options) ->
    super()
    @vote_order = (
      [v, @votes[v]] for v in ["yes", "weak_yes", "discuss", "no", "block", "abstain"]
    )

    resolve.model.on "change", @proposalChanged, this
    intertwinkles.user.on "change", =>
      @postRender()
    , this
    intertwinkles.socket.on "proposal_change", @onProposalData

  remove: =>
    intertwinkles.socket.removeAllListeners("proposal_change")
    resolve.model.off(null, null, this)
    intertwinkles.user.off(null, null, this)
    (view.remove() for key,view of @twinkle_map or {})
    super()

  onProposalData: (data) =>
    resolve.model.set(data.proposal)

  proposalChanged: =>
    changes = resolve.model.changedAttributes()
    if changes._id?
      @render()
    else
      if changes.revisions? or changes.resolved? or changes.revisions? or changes.sharing?
        @postRender()

  render: =>
    if not resolve.model.id?
      return @$el.html("<img src='/static/img/spinner.gif' /> Loading...")
    @$el.html @template({ vote_order: @vote_order })
    @addView ".room-users", new intertwinkles.RoomUsersMenu(room: resolve.model.id)

    sharingButton = new intertwinkles.SharingSettingsButton(model: resolve.model)
    # Handle changes to sharing settings.
    sharingButton.on "save", (sharing_settings) =>
      intertwinkles.socket.once "proposal_saved", (data) =>
        resolve.model.set(data.proposal)
        sharingButton.close()
      intertwinkles.socket.emit "save_proposal", {
        action: "update"
        proposal: _.extend(resolve.model.toJSON(), {sharing: sharing_settings})
        callback: "proposal_saved"
      }
    @addView ".sharing", sharingButton
    @postRender()
    @buildTimeline()
    _timeline_timeout = null
    buildWithTimeout = =>
      clearTimeout(_timeline_timeout) if _timeline_timeout?
      _timeline_timeout = setTimeout @buildTimeline, 1000
    resolve.model.on "change", buildWithTimeout, this

  postRender: =>
    @renderProposal()
    @renderOpinions()
    @setVisibility()
    @twinkle_map = intertwinkles.twinklify(".proposal-page", @twinkle_map)

  renderProposal: =>
    rev = resolve.model.get("revisions")?[0]
    if rev?
      @$(".proposal .text").html(intertwinkles.markup(rev.text))
      @$(".proposal .editors").html("by " + (
        @renderUser(r.user_id, r.name) for r in resolve.model.get("revisions")
      ).join(", "))
      @$(".proposal-twinkle-holder").html("
        <span class='twinkles'
              data-application='resolve'
              data-entity='#{resolve.model.id}'
              data-subentity='#{rev._id}'
              data-recipient='#{rev.user_id}'
              data-url='#{window.location.pathname}'></span>")

      @addView ".proposal .date-auto", new intertwinkles.AutoUpdatingDate(rev.date)
      @userChoice = new intertwinkles.UserChoice()
      @addView(".edit-response-modal .name-input", @userChoice)
      title = resolve.model.get("revisions")[0].text.split(" ").slice(0, 20).join(" ") + "..."
      $("title").html "Proposal: #{title}"

    resolved = resolve.model.get("resolved")
    if resolved?
      @$(".resolution").toggleClass("alert-success", resolve.model.get("passed"))
      @$(".resolution .resolved-date").html(
        "<nobr>" +
        new Date(resolved).toString("htt dddd, MMMM dd, yyyy") + "</nobr>")

  _getOwnOpinion: =>
    return _.find resolve.model.get("opinions"), (o) ->
        o.user_id == intertwinkles.user.id

  renderOpinions: =>
    if intertwinkles.is_authenticated() and intertwinkles.can_edit(resolve.model)
      ownOpinion = @_getOwnOpinion()
      if not ownOpinion?
        @$(".respond-link").addClass("btn-primary").html("Vote now")
      else
        @$(".respond-link")
          .removeClass("btn-primary")
          .html("Change vote")

    first_load = not @_renderedOpinions?
    @_renderedOpinions or= {}
    @_opinionRevs or= {}

    opinions = resolve.model.get("opinions").slice()
    opinions = _.sortBy opinions, (o) -> new Date(o.revisions[0].date).getTime()
    
    # Handle deletions
    deleted = _.difference _.keys(@_renderedOpinions), _.map(opinions, (o) -> o._id)
    for opinion_id in deleted
      @_renderedOpinions[opinion_id].fadeOut 800, =>
        @_renderedOpinions[opinion_id].remove()
        delete @_renderedOpinions[opinion_id]

    # Handle the rest
    for opinion in opinions
      is_non_voting = (
        resolve.model.get("sharing")?.group_id? and
        intertwinkles.is_authenticated() and
        intertwinkles.groups[resolve.model.get("sharing").group_id]? and
        not _.find(
          intertwinkles.groups[resolve.model.get("sharing").group_id].members,
          (m) -> m.user == opinion.user_id
        )?.voting

      )
      rendered = $(@opinionTemplate({
        _id: opinion._id
        rev_id: opinion.revisions[0]._id
        proposal_id: resolve.model.id
        user_id: opinion.user_id
        rendered_user: @renderUser(opinion.user_id, opinion.name)
        vote_value: opinion.revisions[0].vote
        vote_display: @votes[opinion.revisions[0].vote]
        rendered_text: intertwinkles.markup(opinion.revisions[0].text)
        is_non_voting: if is_non_voting then true else false
        stale: (
          new Date(opinion.revisions[0].date) <
          new Date(resolve.model.get("revisions")[0].date)
        )
      }))
      if not @_renderedOpinions[opinion._id]?
        $(".opinions").prepend(rendered)
        @_renderedOpinions[opinion._id] = rendered
        unless first_load
          $("##{opinion._id}").effect("highlight", {}, 3000)
        @_opinionRevs[opinion._id] = opinion.revisions.length
      else
        @_renderedOpinions[opinion._id].replaceWith(rendered)
        @_renderedOpinions[opinion._id] = rendered
        if @_opinionRevs[opinion._id] != opinion.revisions.length
          $("##{opinion._id}").effect("highlight", {}, 3000)
        @_opinionRevs[opinion._id] = opinion.revisions.length

      @addView("##{opinion._id} .date",
        new intertwinkles.AutoUpdatingDate(opinion.revisions[0].date))

    @renderTallies()

  setVisibility: =>
    resolved = resolve.model.get("resolved")?
    passed = resolve.model.get("passed")
    can_edit = intertwinkles.can_edit(resolve.model)
    ownOpinion = @_getOwnOpinion()
    is_stale = (
      ownOpinion? and
      new Date(ownOpinion.revisions[0].date) <
      new Date(resolve.model.get("revisions")[0].date)
    )
    @$(".edit-proposal, .finalize-proposal").toggle(can_edit and (not resolved))
    @$(".reopen-proposal").toggle(can_edit)
    @$(".respond-link").toggle(can_edit and (not resolved) and (not is_stale))
    @$(".confirm-prompt").toggle(can_edit and is_stale and (not resolved))
    @$(".resolution").toggle(resolved)
    @$(".resolution-passed").toggle(resolved and passed)
    @$(".resolution-failed").toggle(resolved and (not passed))
    @$(".edit-links a").toggle(can_edit and (not resolved))

  renderTallies: =>
    by_vote = {}
    total_count = 0
    for opinion in resolve.model.get("opinions")
      by_vote[opinion.revisions[0].vote] or= []
      by_vote[opinion.revisions[0].vote].push(opinion)
      total_count += 1

    # Don't bother counting "non-voting" if it doesn't make sense: e.g. if
    # we're not a member of the owning group and thus can't see whether someone
    # is a voting member or not, or if this proposal is not owned by a group,
    # and thus there's no notion of voting or non-.
    show_non_voting = (
      resolve.model.get("sharing")?.group_id? and
      intertwinkles.is_authenticated() and
      intertwinkles.groups[resolve.model.get("sharing").group_id]?
    )

    group = intertwinkles.groups?[resolve.model.get("sharing")?.group_id]
    tallies = []
    for [vote_value, vote_display] in @vote_order
      votes = by_vote[vote_value] or []
      non_voting = []
      stale = []
      current = []
      for opinion in votes
        rendered = @renderUser(opinion.user_id, opinion.name)
        if show_non_voting and not _.find(group.members, (m) -> m.user == opinion.user_id)?.voting
          non_voting.push(rendered)
        else
          if new Date(opinion.revisions[0].date) < new Date(resolve.model.get("revisions")[0].date)
            stale.push(rendered)
          else
            current.push(rendered)
      count = non_voting.length + stale.length + current.length
      tally = {
        vote_display: vote_display
        className: vote_value
        count: current.length + stale.length + non_voting.length
        counts: [{
          className: vote_value + " current"
          title: "#{current.length} Current vote#{if current.length == 1 then "" else "s"}"
          content: current.join(", ")
          count: current.length
        }, {
          className: vote_value + " stale"
          title: "#{stale.length} Stale vote#{if stale.length == 1 then "" else "s"}"
          content: (
            "<i>The proposal was edited after these people voted:</i><br />#{stale.join(", ")}"
          )
          count: stale.length
        }, {
          className: vote_value + " non-voting"
          title: "#{non_voting.length} Advisory response#{if non_voting.length == 1 then "" else "s"}"
          content: (
            "<i>These people are non-members or " +
            "non-voting:</i><br />#{non_voting.join(", ")}"
          )
          count: non_voting.length
        }]
      }
      tallies.push(tally)
    if show_non_voting
      # Missing count
      found_user_ids = []
      for opinion in resolve.model.get("opinions")
        if opinion.user_id?
          found_user_ids.push(opinion.user_id)
      missing = _.difference(
        _.map(
          intertwinkles.groups[resolve.model.get("sharing").group_id].members,
          (m) -> m.user
        )
        found_user_ids
      )
      total_count += missing.length
      tally = {
        vote_display: "Haven't voted yet"
        className: "missing"
        count: missing.length
        counts: [{
          className: "missing"
          title: "Haven't voted yet"
          content: "<i>The following people haven't voted yet:</i><br />" + (
            @renderUser(user_id, "Protected") for user_id in missing
          ).join(", ")
          count: missing.length
        }]
      }
      tallies.push(tally)

    for tally in tallies
      for type in tally.counts
        type.percentage = 100 * type.count / total_count
    @$(".tallies").html(@talliesTemplate({tallies}))
    @$("[rel=popover]").popover()

  showEditProposalForm: (event) =>
    event.preventDefault()
    if intertwinkles.is_authenticated()
      @$(".edit-proposal-modal [name=revision_user_id]").val(intertwinkles.user.id)
      @$(".edit-proposal-modal .name-field-group").hide()
    else
      @$(".edit-proposal-modal [name=revision_user_id]").val("")
      @$(".edit-proposal-modal .name-field-group").show()
    @$(".edit-proposal-modal").modal('show')
    @$(".edit-proposal-modal textarea").val(resolve.model.get("revisions")[0].text)

  saveProposalRevision: (event) =>
    event.preventDefault()

    cleanedData = @validateFields "form.edit-proposal", [
      ["[name=revision_name]", (val) ->
          if @$("[name=revision_user_id]").val()
            return ""
          return val or null
        , "This field is required."],
      ["[name=proposal_revision]", ((val) -> val or null), "This field is required."]
    ]
    return if cleanedData == false

    @_saveProposal event, {
      proposal: cleanedData.proposal_revision
      name: cleanedData.revision_name
      user_id: @$("[name=revision_user_id]").val()
    }, =>
      @$(".edit-proposal-modal").modal('hide')

  finalizeProposal: (event) =>
    event.preventDefault()
    @$(".finalize-proposal-modal").modal('show')

  proposalPassed: (event) =>
    @_saveProposal event, {passed: true}, =>
      @$(".finalize-proposal-modal").modal('hide')

  proposalFailed: (event) =>
    @_saveProposal event, {passed: false}, =>
      @$(".finalize-proposal-modal").modal('hide')

  showReOpenProposalForm: (event) =>
    event.preventDefault()
    @$(".reopen-proposal-modal").modal('show')

  reOpenProposal: (event) =>
    @_saveProposal event, {reopened: true}, =>
      @$(".reopen-proposal-modal").modal('hide')

  _saveProposal: (event, changes, done) =>
    event.preventDefault()
    @$(event.currentTarget).addClass("loading").attr("disabled", true)
    callback = "update_proposal"+ new Date().getTime()

    intertwinkles.socket.once callback, (data) =>
      @$(event.currentTarget).removeClass("loading").attr("disabled", false)
      if data.error?
        flash "error", "Uh-oh, there was a server error. SRY!!!"
        console.info(data.error)
      else
        resolve.model.set(data.proposal)
      done?()

    update = _.extend {}, changes, {_id: resolve.model.id}
    intertwinkles.socket.emit "save_proposal", {
      action: "update"
      proposal: update
      callback: callback
    }

  showDeleteOpinionForm: (event) =>
    event.preventDefault()
    opinion_id = $(event.currentTarget).attr("data-id")
    opinion = _.find resolve.model.get("opinions"), (o) -> o._id == opinion_id
    return unless opinion?
    rendered_user = @renderUser(opinion.user_id, opinion.name)
    @$("form.delete-opinion .rendered-user").html(rendered_user)
    @$("form.delete-opinion [name=opinion_id]").val(opinion_id)
    @$(".delete-opinion-modal").modal('show')

  deleteOpinion: (event) =>
    event.preventDefault()
    opinion_id = @$("form.delete-opinion [name=opinion_id]").val()
    submit = @$("form.delete-opinion input[type=submit]")
    submit.addClass("loading").attr("disabled", true)

    intertwinkles.socket.once "opinion_deleted", (data) =>
      submit.removeClass("loading").attr("disabled", false)
      @$("form.delete-opinion [name=opinion_id]").val("")
      @$(".delete-opinion-modal").modal('hide')
      if data.error?
        console.info("error", data.error)
        flash "error", "Uh-oh. The server had an error."
      else
        resolve.model.set(data.proposal)

    intertwinkles.socket.emit "save_proposal", {
      callback: "opinion_deleted"
      action: "trim"
      proposal: { _id: resolve.model.id }
      opinion: { _id: opinion_id }
    }

  editOpinion: (event) =>
    @showOpinionForm(event)

  showOpinionForm: (event) =>
    event.preventDefault()
    opinion_id = $(event.currentTarget).attr("data-id")
    if opinion_id?
      opinion = _.find(resolve.model.get("opinions"), (o) -> o._id == opinion_id)
      rev = opinion.revisions[0]
      @$("#id_vote").val(rev.vote)
      @$("#id_text").val(rev.text)
      @userChoice.set(opinion.user_id, opinion.name)
    else
      @$("#id_vote").val("")
      @$("#id_text").val("")
      @userChoice.set(intertwinkles.user.id, intertwinkles.user.get("name"))

    @$(".edit-response-modal").modal()

  saveOpinion: (event) =>
    event.preventDefault()
    cleaned_data = @validateFields "form.weigh-in", [
      ["#id_user_id", ((val) -> val or ""), ""]
      ["#id_user", ((val) -> val or null), "This field is required"]
      ["#id_vote", ((val) -> val or null), "This field is required"]
      ["#id_text", ((val) -> val or null), "This field is required"]
    ]
    return if cleaned_data == false

    @$("form.weigh-in input[type=submit]").addClass("loading").attr("disabled", true)

    intertwinkles.socket.once "save_complete", (data) =>
      @$("form.weigh-in input[type=submit]").removeClass("loading").attr("disabled", false)
      @$(".edit-response-modal").modal('hide')
      if data.error?
        flash "error", "Oh noes.. There seems to be a server malfunction."
        console.info(data.error)
        return
      @onProposalData(data)

    intertwinkles.socket.emit "save_proposal", {
      callback: "save_complete"
      action: "append"
      proposal: {
        _id: resolve.model.id
      }
      opinion: {
        user_id: cleaned_data.user_id
        name: cleaned_data.name
        vote: cleaned_data.vote
        text: cleaned_data.text
      }
    }

  confirmMyVote: (event) =>
    ownOpinion = @_getOwnOpinion()
    $(event.currentTarget).attr("data-id", ownOpinion._id)
    @showOpinionForm(event)

  buildTimeline: =>
    if resolve.model.id
      callback = "resolve_events_#{resolve.model.id}"
      intertwinkles.socket.once callback, (data) =>
        collection = new intertwinkles.EventCollection()
        for event in data.events
          event.date = new Date(event.date)
          collection.add new intertwinkles.Event(event)
        intertwinkles.build_timeline @$(".timeline-holder"), collection, (event) ->
          user = intertwinkles.users?[event.user]
          via_user = intertwinkles.users?[event.via_user]
          via_user = null if via_user? and via_user.id == user?.id
          if user?
            icon = "<img src='#{user.icon.tiny}' />"
          else
            icon = "<i class='icon-user'></i>"
          switch event.type
            when "create"
              title = "Proposal created"
              content = "#{user?.name or "Anonymous"} created this proposal."
            when "visit"
              title = "Visit"
              content = "#{user?.name or "Anonymous"} stopped by."
            when "append"
              title = "Response added"
              if via_user?
                content = "#{user?.name or event.data.name} responded (via #{via_user.name})."
              else
                content = "#{user?.name or event.data.name} responded."
            when "update"
              title = "Proposal updated"
              content = "#{user?.name or "Anonymous"} updated the proposal."
            when "trim"
              title = "Response removed"
              content = "#{user?.name or "Anonymous"} removed
                        the response by #{event.data.deleted_opinion.name}."
          return """
            <a class='#{ event.type }' rel='popover' data-placement='bottom'
              data-trigger='hover' title='#{ title }'
              data-content='#{ content }'>#{ icon }</a>
          """
      intertwinkles.socket.emit "get_proposal_events", {
        callback: callback
        proposal_id: resolve.model.id
      }

class Router extends Backbone.Router
  routes:
    'p/:id/':   'room'
    'new/':        'newProposal'
    '':           'index'

  index: =>
    view = new SplashView()
    if @view?
      # Re-fetch proposal list if this isn't a first load.
      intertwinkles.socket.once("proposal_list", (data) =>
        intertwinkles.listed_proposals = data.proposals
        view.render()
      )
      intertwinkles.socket.emit "get_proposal_list", {callback: "proposal_list"}
    @_display(view)
    $("title").html "Resolve: Decide Something"
        

  newProposal: =>
    @_display(new AddProposalView())

  room: (id) =>
    if resolve.model?.id != id
      resolve.model = new Proposal()
      intertwinkles.socket.once "load_proposal", (data) ->
        resolve.model.set(data.proposal)
      intertwinkles.socket.emit "get_proposal",
        proposal: {_id: id}
        callback: "load_proposal"
    @_display(new ShowProposalView(id: id))

  _display: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view


socket = io.connect("/iorooms")
socket.on "error", (data) ->
  flash "error", "Oh noes, server error."
  window.console?.log?(data.error)

socket.on "connect", ->
  resolve.socket = intertwinkles.socket = socket
  unless resolve.started == true
    resolve.app = intertwinkles.app = new Router()
    Backbone.history.start(pushState: true)
    resolve.started = true
