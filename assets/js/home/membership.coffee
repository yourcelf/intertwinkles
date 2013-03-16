EMAIL_RE = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i

membershipTableTemplate = _.template("""
<table class='table'>
  <tr>
    <th>User</th>
    <th>Voting <i class='icon-question-sign voting'></i></th>
    <th>Role <i class='icon-question-sign role'></i></th>
    <th></th>
  </tr>
  <tr class='members-header'></tr>
  <tr class='has-been-invited-header'>
    <td class='4'><h3>Has been invited:</h3></td>
  </tr>
  <tr class='to-be-invited-header'>
    <td colspan='4'><h3>To be invited</h3>
  </tr>
  <tr class='add-row'>
    <td class='add-email'>
      <input type='email' placeholder='Email' id='add_email' /><br />
      <a class='btn add-new-invitee' href='#'><i class='icon-plus'></i> Add</a> 
    </td>
    <td>
      <label>
        <input type='checkbox' checked='checked' id='add_voting' />
        Can Vote
      </label>
    </td>
    <td>
      <input type='text' placeholder='Optional' id='add_role' />
    </td>
    <td></td>
  </tr>
</table>
""")
      

membershipRowTemplate = _.template("""
  <tr class='member<%- removed ? " removed" : "" %><%- new_invitee ? " newinvite" : "" %>'>
    <td>
      <% if (user && user.icon) { %>
        <img src='<%- user.icon.small %>' /> <%- user.name %>
      <% } else { %>
        <%- email %>
      <% } %>
    </td>
    <td class='<%- voting_changed ? 'changed' : '' %>'>
      <label>
        <input class='voting' type='checkbox' data-email='<%- email %>'
          <%- voting ? 'checked' : "" %> />
        Can vote
      </label>
    </td>
    <td class='<%- role_changed ? "changed" : "" %>'>
      <input type='text' data-email='<%- email %>'
             value='<%- role %>' placeholder='Optional' class='role' />
    </td>
    <td class='link'>
      <a href='#' data-email='<%- email %>' class='remove'>
        <%- removed ? 'undo' : 'remove' %>
      </a>
    </td>
  </tr>
""")


class MembershipTable extends Backbone.View
  template: membershipTableTemplate
  membershipRowTemplate: membershipRowTemplate
  events:
    'keydown #add_email, #add_role': 'triggerKeyDown'
    'change #add_email': 'validateEmail'
    'change input.role': 'updateRole'
    'change input.voting': 'updateVoting'
    'click .remove': 'removeMember'
    'click .add-new-invitee': 'addMember'

  initialize: (options={}) ->
    @users = intertwinkles.users
    @user = intertwinkles.user
    @destination_selector = options.destination_selector
    if options.group_id?
      # Zombie wasn't re-parsing initial data (reparsing intertwinkles js)
      # other browsers too?
      #@group = intertwinkles.groups[options.group_id] or INITIAL_DATA.groups[options.group_id]
      @group = intertwinkles.groups[options.group_id]
    else
      @group = {
        members: [{user: @user.id, role: "", voting: true}]
      }
    @change_set = {
      'remove': {}
      'add': {}
      'update': {}
    }

  render: =>
    @$el.html(@template())
    @$(".role").popover({
      html: true
      placement: "bottom"
      trigger: "hover"
      title: "Role"
      content: "Roles are labels next to your name, such as 'president' or 'secretary'."
    })
    @$(".voting").popover({
      html: true
      placement: "bottom"
      trigger: "hover"
      title: "Voting"
      content: "By default, every member can vote.  If you uncheck <nobr>'Can vote'</nobr>, the member's votes will be counted separately."
    })
    @renderMembers()

  renderMembers: =>
    @$("tr.member").remove()
    
    # Existing members
    @$(".members-header").after((@membershipRowTemplate({
      email: @users[member.user].email
      user: @users[member.user]
      voting: if @change_set.update[@users[member.user].email]?.voting? then not member.voting else member.voting
      voting_changed: @change_set.update[@users[member.user].email]?.voting?
      role: @change_set.update[@users[member.user].email]?.role or member.role
      role_changed: @change_set.update[@users[member.user].email]?.role?
      new_invitee: false
      removed: @change_set.remove[@users[member.user].email]?
    }) for member in @group.members))

    # New invitees
    @$(".to-be-invited-header").after((@membershipRowTemplate({
      email: email
      user: null
      voting: new_invitee.voting
      voting_changed: false
      role: new_invitee.role
      role_changed: false
      new_invitee: true
      removed: false
    }) for email, new_invitee of @change_set.add))

    # Existing invitees
    for invitee in @group.invited_members or []
      email = invitee.user?.email or @users[invitee.user].email
      @$(".has-been-invited-header").after(@membershipRowTemplate({
        email: email
        user: null
        voting: if @change_set.update[email]?.voting? then not invitee.voting else invitee.voting
        voting_changed: @change_set.update[email]?
        role: @change_set.update[email]?.role or invitee.role
        role_changed: @change_set.update[email]?.role?
        new_invitee: false
        removed: @change_set.remove[invitee.user.email]?
      }))

    @$(".has-been-invited-header").toggle(@group.invited_members?.length > 0)
    @$(".to-be-invited-header").toggle(_.keys(@change_set.add).length > 0)

  triggerKeyDown: (event) =>
    if event.keyName() == '\r'
      event.preventDefault()
      if $.trim($(event.currentTarget).val()) != ""
        @addMember(event)
        @$("#add_email").select()

  validateEmail: (event) =>
    td = @$("td.add-email")
    td.removeClass("error")
    td.find(".error-msg").remove()
    email = $.trim(@$("#add_email").val())
    return unless email
    valid = EMAIL_RE.test(email)
    unless valid
      td.addClass("error")
      td.append("<span class='help-inline error-msg'>This doesn't look like a valid email...</span>")

  updateChangeSet: (email, key, val) =>
    member  = (
      _.find(@group.members, (m) => @users[m.user].email == email) or
      _.find(@group.invited_members, (m) -> m.email == email)
    )
    new_invitee = @change_set.add[email]
    if member?
      if val == member[key]
        delete @change_set.update[email][key] if @change_set.update[email]?[key]?
      else
        @change_set.update[email] or= {}
        @change_set.update[email][key] = val
    else if new_invitee
      @change_set.add[email] or= {}
      @change_set.add[email][key] = val

  updateRole: (event) =>
    email = $(event.currentTarget).attr("data-email")
    val = $(event.currentTarget).val()
    @updateChangeSet(email, "role", val)
    @renderMembers()
    @saveChangeSet()

  updateVoting: (event) =>
    email = $(event.currentTarget).attr("data-email")
    val = $(event.currentTarget).is(":checked")
    @updateChangeSet(email, "voting", val)
    @renderMembers()
    @saveChangeSet()

  removeMember: (event) =>
    event.preventDefault()
    email = $(event.currentTarget).attr("data-email")
    if @change_set.add[email]?
      # New invitees: Just flat out remove.
      delete @change_set.add[email]
    else if @change_set.remove[email]?
      # Already marked for removal: toggle.
      delete @change_set.remove[email]
    else
      if (email == intertwinkles.user.get("email") and
            (@group.members.length - _.keys(@change_set.remove).length) < 2)
        flash "info", "There must be other group members before you can remove yourself."
        return
      # Not marked for removal yet: toggle.
      @change_set.remove[email] = true
    @renderMembers()
    @saveChangeSet()

  addMember: (event) =>
    event.preventDefault()
    @validateEmail(event)
    email = $.trim(@$("#add_email").val())
    role = @$("#add_role").val()
    voting = @$("#add_voting").is(":checked")
    email_td = @$("#add_email").parent()

    if email_td.hasClass("error")
      console.info "error"
      return
    else if _.find(@group.members, (m) => @users[m.user]?.email == email)?
      email_td.addClass("error")
      flash "info", "That user is already a member."
    else if _.find(@group.invited_members, (m) => @users[m.user]?.email == email)?
      email_td.addClass("error")
      flash "info", "That user has already been invited."
    else
      @change_set.add[email] = {
        email: email
        role: role
        voting: voting
        invited_by: @user.id
        invited_on: new Date()
      }
      @$("#add_email").val("")
      @$("#add_role").val("")
      @$("#add_voting").attr("checked", true)
      @renderMembers()
    @saveChangeSet()

  saveChangeSet: =>
    if @destination_selector?
      $(@destination_selector).val(JSON.stringify(@change_set))

window.MembershipTable = MembershipTable
