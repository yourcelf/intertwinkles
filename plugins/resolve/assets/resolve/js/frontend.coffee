resolve = window.resolve = {}

class Proposal extends Backbone.Model
  idAttribute: "_id"
class ProposalCollection extends Backbone.Collection
  model: Proposal
  comparator: (p) ->
    return intertwinkles.parse_date(p.get("revisions")[0].date).getTime()

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
    @listenTo intertwinkles.user, "change", @getProposalList
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
            url: "/resolve/p/#{proposal._id}/"
            proposal: proposal
            group: intertwinkles.groups?[proposal.sharing?.group_id]
          })
          selector.append(listing)
    @$(".proposal-listing-date").each =>
      @addView this, new intertwinkles.AutoUpdatingDate(date: $(this).attr("data-date"))


  getProposalList: =>
    @listenTo resolve.socket, "list_proposals", (data) =>
      if data.error?
        flash "error", "The server. It has got confused."
      else
        resolve.listed_proposals = data.proposals
        @render()
    resolve.socket.send "resolve/get_proposal_list", {
      callback: "list_proposals"
    }

class AddProposalView extends intertwinkles.BaseView
  template: _.template($("#addProposalTemplate").html())
  events: _.extend {
    'submit   form': 'saveProposal'
  }, intertwinkles.BaseEvents

  initialize: ->
    @listenTo intertwinkles.user, "change", @onUserChange
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

    resolve.socket.once callback, (data) =>
      return handle_error(data) if data.error?
      @$("[type=submit]").removeClass("loading").attr("disabled", false)
      resolve.model.set(data.proposal)
      resolve.app.navigate "/resolve/p/#{data.proposal._id}/", trigger: true

    @$("[type=submit]").addClass("loading").attr("disabled", true)
    resolve.socket.send "resolve/save_proposal", {
      callback: callback,
      proposal: cleaned_data
      action: "create"
    }

class EditProposalDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#editProposalDialogTemplate").html()

class FinalizeProposalDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#finalizeProposalDialogTemplate").html()
  events:
    "click [name=passed]": "passed"
    "click [name=failed]": "failed"
  passed: (event) =>
    event.preventDefault()
    @trigger "passed"
  failed: (event) =>
    event.preventDefault()
    @trigger "failed"


class ReopenProposalDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#reopenProposalDialogTemplate").html()

class EditOpinionDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#editOpinionDialogTemplate").html()
  render: =>
    super()
    @addView(".name-input", new intertwinkles.UserChoice(model: {
      user_id: @context.user_id
      name: @context.name
    }))

class DeleteOpinionDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#deleteOpinionDialogTemplate").html()

class ProposalHistoryView extends intertwinkles.BaseModalFormView
  template: _.template $("#proposalHistoryViewTemplate").html()

  initialize: (options) ->
    @model = options.model
    @vote_map = options.vote_map

  render: =>
    # Get a listing of the revisions, and the latest opinion by each author for
    # that revision.
    revs = _.map @model.get("revisions"), (rev) =>
      return { revision: rev, opinions: {} }
    _.each revs, (cur, i) ->
      next = revs[i + 1]
      if next
        dmp = new diff_match_patch()
        dmp.Diff_EditCost = 4
        diff = dmp.diff_main(next.revision.text, cur.revision.text)
        dmp.diff_cleanupSemantic(diff)
        cur.diff = dmp.diff_prettyHtml(diff)
      else
        cur.diff = cur.revision.text

    for i in [(revs.length - 1)..0]
      cur = revs[i]
      cur_date = intertwinkles.parse_date(cur.revision.date)
      next = revs[i - 1]
      if next?
        next_date = intertwinkles.parse_date(next.revision.date)
      else
        next_date = undefined
      _.each @model.get("opinions"), (op) =>
        for j in [0...op.revisions.length]
          rev = op.revisions[j]
          rev_date = intertwinkles.parse_date(rev.date)
          if rev_date > cur_date and ((not next_date?) or rev_date < next_date)
            cur.opinions[rev.vote] ?= []
            cur.opinions[rev.vote].push({
              opinion: op
              revision: rev
            })
            break

    # Add proposal resolutions, and sort.
    revs = revs.concat(@model.get("resolutions") or [])
    revs = _.sortBy(revs, (r) ->
      -intertwinkles.parse_date(r.revision?.date or r.date).getTime()
    )

    @context = {revs: revs, vote_map: @vote_map}
    super()
    intertwinkles.sub_vars(@$el)
    @$("[rel=popover]").popover()

class ShowProposalView extends intertwinkles.BaseView
  template: _.template($("#showProposalTemplate").html())
  opinionTemplate: _.template($("#opinionTemplate").html())
  talliesTemplate: _.template($("#talliesTemplate").html())
  events: _.extend {
    'click button.edit-proposal': 'editProposal'
    'click   .finalize-proposal': 'finalizeProposal'
    'click     .reopen-proposal': 'reopenProposal'
    'click        .respond-link': 'editOpinion'
    'click        .edit-opinion': 'editOpinion'
    'click     a.delete-opinion': 'deleteOpinion'
    'click     .confirm-my-vote': 'confirmMyVote'
    'click             .history': 'showProposalHistory'
  }, intertwinkles.BaseEvents

  votes: {
    yes: "Strongly approve"
    weak_yes: "Approve with reservations"
    discuss: "Need more discussion"
    no: "Have concerns"
    block: "Block"
    abstain: "I have a conflict of interest"
  }
  vote_order: ["yes", "weak_yes", "discuss", "no", "block", "abstain"]

  initialize: (options) ->
    super()
    @vote_map = ([v, @votes[v]] for v in @vote_order)
    @listenTo resolve.model, "change", @proposalChanged
    @listenTo intertwinkles.user, "change", @postRender
    @listenTo resolve.socket, "proposal_change", @onProposalData

  onProposalData: (data) =>
    resolve.model.set(data.proposal)

  proposalChanged: =>
    changes = resolve.model.changedAttributes()
    if changes._id?
      @render()
    else
      @postRender()

  render: =>
    if not resolve.model.id?
      return @$el.html("<img src='/static/img/spinner.gif' /> Loading...")
    @$el.html @template({ vote_map: @vote_map })
    @roomUsersMenu =  new intertwinkles.RoomUsersMenu({
      room: "resolve/" + resolve.model.id
    })
    @addView ".room-users", @roomUsersMenu

    sharingButton = new intertwinkles.SharingSettingsButton({
      model: resolve.model
      application: "resolve"
    })
    # Handle changes to sharing settings.
    sharingButton.on "save", (sharing_settings) =>
      resolve.socket.once "proposal_saved", (data) =>
        resolve.model.set(data.proposal)
        sharingButton.close()
      resolve.socket.send "resolve/save_proposal", {
        action: "update"
        proposal: _.extend(resolve.model.toJSON(), {sharing: sharing_settings})
        callback: "proposal_saved"
      }
    @addView ".sharing", sharingButton
    @postRender()
    @showEvents()
    _events_timeout = null
    buildWithTimeout = =>
      clearTimeout(_timeline_timeout) if _timeline_timeout?
      _events_timeout = setTimeout @showEvents, 1000
    @listenTo resolve.model, "change", buildWithTimeout

  postRender: =>
    @renderProposal()
    @renderOpinions()
    @setVisibility()
    @twinkle_map = intertwinkles.twinklify("resolve", ".proposal-page", @twinkle_map)

  renderProposal: =>
    rev = resolve.model.get("revisions")?[0]
    if rev?
      @$(".proposal .text").html(intertwinkles.markup(rev.text))
      @$(".proposal .editors").html("by " + _.unique(
        @renderUser(r.user_id, r.name) for r in resolve.model.get("revisions")
      ).join(", "))
      @$(".proposal-twinkle-holder").html("
        <span class='twinkles'
              data-application='resolve'
              data-entity='#{resolve.model.id}'
              data-subentity='#{rev._id}'
              data-recipient='#{rev.user_id or ""}'
              data-url='#{resolve.model.get("url")}'></span>")

      @addView ".proposal .date-auto", new intertwinkles.AutoUpdatingDate(date: rev.date)
      title = resolve.model.get("revisions")[0].text.split(" ").slice(0, 20).join(" ") + "..."
      $("title").html "Proposal: #{title}"

    resolved = resolve.model.get("resolved")
    if resolved?
      @$(".resolution").toggleClass("alert-success", resolve.model.get("passed"))
      @$(".resolution .resolved-date").html(
        intertwinkles.simple_date(resolve.model.get("resolved"))
      )
      res = resolve.model.get("resolutions")?[0]
      if res?
        @$(".resolver").html("by " + intertwinkles.inline_user(res.user_id, res.name))
        @$(".resolution-message").html(res.message or "")

    @$(".history").toggle(resolve.model.get("revisions").length > 1)

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
    opinions = _.sortBy opinions, (o) -> intertwinkles.parse_date(o.revisions[0].date).getTime()
    
    # Handle deletions
    deleted = _.difference _.keys(@_renderedOpinions), _.map(opinions, (o) -> o._id)
    for opinion_id in deleted
      @_renderedOpinions[opinion_id].fadeOut 800, =>
        @_renderedOpinions[opinion_id].remove()
        delete @_renderedOpinions[opinion_id]

    # Handle the rest
    _.each opinions, (opinion) =>
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
        num_revs: opinion.revisions.length
        rev_id: opinion.revisions[0]._id
        proposal_id: resolve.model.id
        proposal_url: resolve.model.get("url")
        user_id: opinion.user_id
        rendered_user: @renderUser(opinion.user_id, opinion.name)
        vote_value: opinion.revisions[0].vote
        vote_display: @votes[opinion.revisions[0].vote]
        rendered_text: intertwinkles.markup(opinion.revisions[0].text)
        is_non_voting: if is_non_voting then true else false
        stale: (
          intertwinkles.parse_date(opinion.revisions[0].date) <
          intertwinkles.parse_date(resolve.model.get("revisions")[0].date)
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
        new intertwinkles.AutoUpdatingDate(date: opinion.revisions[0].date))


    @renderTallies()

  setVisibility: =>
    resolved = resolve.model.get("resolved")?
    passed = resolve.model.get("passed")
    can_edit = intertwinkles.can_edit(resolve.model)
    ownOpinion = @_getOwnOpinion()
    is_stale = (
      ownOpinion? and
      intertwinkles.parse_date(ownOpinion.revisions[0].date) <
      intertwinkles.parse_date(resolve.model.get("revisions")[0].date)
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
    for [vote_value, vote_display] in @vote_map
      votes = by_vote[vote_value] or []
      non_voting = []
      stale = []
      current = []
      for opinion in votes
        rendered = @renderUser(opinion.user_id, opinion.name)
        if show_non_voting and not _.find(group.members, (m) -> m.user == opinion.user_id)?.voting
          non_voting.push(rendered)
        else
          if intertwinkles.parse_date(opinion.revisions[0].date) < intertwinkles.parse_date(resolve.model.get("revisions")[0].date)
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

  editProposal: (event) =>
    event.preventDefault()
    validation = [
      ["[name=proposal_revision]", ((v) -> v or null), "This field is required."]
    ]
    if not intertwinkles.is_authenticated()
      validation.push(["[name=revision_name]", ((v) -> v or null), "Please add your name."])
    form = new EditProposalDialog({
      context: { revision: resolve.model.get("revisions")[0].text }
      validation: validation
    })
    form.render()
    form.on "submitted", (cleaned_data) =>
      @_saveProposal {
        proposal: cleaned_data.proposal_revision
        name: cleaned_data.revision_name
        user_id: if intertwinkles.is_authenticated() then intertwinkles.user.id else undefined
      }, =>
        form.remove()

  finalizeProposal: (event) =>
    event.preventDefault()
    form = new FinalizeProposalDialog()
    form.render()
    form.on "passed", =>
      @_saveProposal {passed: true, message: form.$("#id_message").val()}, form.remove
    form.on "failed", =>
      @_saveProposal {passed: false, message: form.$("#id_message").val()}, form.remove

  reopenProposal: (event) =>
    event.preventDefault()
    form = new ReopenProposalDialog()
    form.render()
    form.on "submitted", =>
      @_saveProposal {reopened: true, message: form.$("#id_message").val()}, form.remove

  _saveProposal: (changes, done) =>
    callback = "update_proposal"+ intertwinkles.now().getTime()

    resolve.socket.once callback, (data) =>
      if data.error?
        flash "error", "Uh-oh, there was a server error. SRY!!!"
        console.info(data.error)
      else
        resolve.model.set(data.proposal)
      done?()

    update = _.extend {}, changes, {_id: resolve.model.id}
    resolve.socket.send "resolve/save_proposal", {
      action: "update"
      proposal: update
      callback: callback
    }

  deleteOpinion: (event) =>
    event.preventDefault()
    opinion_id = $(event.currentTarget).attr("data-id")
    opinion = _.find resolve.model.get("opinions"), (o) -> o._id == opinion_id
    form = new DeleteOpinionDialog()
    form.render()
    form.$(".rendered-user").html(@renderUser(opinion.user_id, opinion.name))
    form.on "submitted", =>
      resolve.socket.once "opinion_deleted", (data) =>
        form.remove()
        if data.error?
          console.info("error", data.error)
          flash "error", "Uh-oh. The server had an error."
        else
          resolve.model.set(data.proposal)

      resolve.socket.send "resolve/save_proposal", {
        callback: "opinion_deleted"
        action: "trim"
        proposal: { _id: resolve.model.id }
        opinion: { _id: opinion_id }
      }

  editOpinion: (event) =>
    opinion_id = $(event.currentTarget).attr("data-id")
    if opinion_id?
      opinion = _.find(resolve.model.get("opinions"), (o) -> o._id == opinion_id)
    else if intertwinkles.is_authenticated()
      opinion = _.find(resolve.model.get("opinions"), (o) ->
        o.user_id == intertwinkles.user.id)

    form = new EditOpinionDialog({
      context: {
        vote_map: @vote_map
        vote: opinion?.revisions[0].vote
        text: opinion?.revisions[0].text
        user_id: if opinion? then opinion?.user_id else intertwinkles.user.id
        name: if opinion? then opinion?.name else intertwinkles.user.get("name")
      }
      validation: [
        ["#id_user_id", ((val) -> val or ""), ""]
        ["#id_user", ((val) -> val or null), "This field is required"]
        ["#id_vote", ((val) -> val or null), "This field is required"]
        ["#id_text", ((val) -> val or null), "This field is required"]
      ]
    })
    form.render()
    form.on "submitted", (cleaned_data) =>
      resolve.socket.once "save_complete", (data) =>
        form.remove()
        if data.error?
          flash "error", "Oh noes.. There seems to be a server malfunction."
          console.info(data.error)
          return
        @onProposalData(data)

      resolve.socket.send "resolve/save_proposal", {
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
    @editOpinion(event)

  showEvents: =>
    if resolve.model.id
      callback = "resolve_events_#{resolve.model.id}"
      resolve.socket.once callback, (data) =>
        collection = intertwinkles.buildEventCollection(data.events)
        summary = new intertwinkles.EventsSummary({
          collection: collection.deduplicate(),
          modificationWhitelist: ["visit", "append", "trim"]
        })
        @$(".events-holder").html(summary.el)
        summary.render()
      resolve.socket.send "resolve/get_proposal_events", {
        callback: callback
        proposal_id: resolve.model.id
      }

  buildTimeline: =>
    if resolve.model.id
      callback = "resolve_events_#{resolve.model.id}"
      resolve.socket.once callback, (data) =>
        collection = new intertwinkles.EventCollection()
        for event in data.events
          event.date = intertwinkles.parse_date(event.date)
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
                content = "#{user?.name or event.data.action.name} responded (via #{via_user.name})."
              else
                content = "#{user?.name or event.data.action.name} responded."
            when "update"
              title = "Proposal updated"
              content = "#{user?.name or "Anonymous"} updated the proposal."
            when "trim"
              title = "Response removed"
              content = "#{user?.name or "Anonymous"} removed
                        the response by #{event.data.action.deleted_opinion.name}."
          return """
            <a class='#{ event.type }' rel='popover' data-placement='bottom'
              data-trigger='hover' title='#{ title }'
              data-content='#{ content }'>#{ icon }</a>
          """
      resolve.socket.send "resolve/get_proposal_events", {
        callback: callback
        proposal_id: resolve.model.id
      }

  showProposalHistory: (event) =>
    event.preventDefault()
    new ProposalHistoryView({model: resolve.model, vote_map: @vote_map}).render()

class Router extends Backbone.Router
  routes:
    'resolve/p/:id/':     'room'
    'resolve/new/':       'newProposal'
    'resolve/':           'index'

  onReconnect: ->
    # override this with appropriate logic to execute when a reconnect happens.

  index: =>
    view = new SplashView()
    if @view?
      # Re-fetch proposal list if this isn't a first load.
      resolve.socket.once("proposal_list", (data) =>
        resolve.listed_proposals = data.proposals
        view.render()
      )
      resolve.socket.send "resolve/get_proposal_list", {callback: "proposal_list"}
    @_display(view)
    $("title").html "Resolve: Decide Something"
    @onReconnect = @index
        

  newProposal: =>
    @_display(new AddProposalView())
    @onReconnect = (->)

  room: (id) =>
    fetch = ->
      resolve.socket.once "load_proposal", (data) ->
        resolve.model.set(data.proposal)
      resolve.socket.send "resolve/get_proposal",
        proposal: {_id: id}
        callback: "load_proposal"
    if resolve.model?.id != id
      resolve.model = new Proposal()
      fetch()
    proposal_view = new ShowProposalView(id: id)
    @_display(proposal_view)
    @onReconnect = ->
      proposal_view.roomUsersMenu.connect()
      fetch()

  _display: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    window.scrollTo(0, 0)
    @view = view

intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "resolve"})
  intertwinkles.build_footer($("footer"))
  resolve.socket = intertwinkles.socket
  unless resolve.started == true
    resolve.app = intertwinkles.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    resolve.started = true
    intertwinkles.socket.on "reconnected", ->
      intertwinkles.socket.once "identified", ->
        resolve.app.onReconnect()
