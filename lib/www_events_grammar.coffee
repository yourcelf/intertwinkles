_ = require("underscore")

comma_and = (strlist) ->
  if strlist.length == 1
    return strlist[0]
  if strlist.length == 2
    return "#{strlist[0]} and #{strlist[1]}"
  return strlist.slice(0, strlist.length - 1).join(", ") + \
    ", and #{strlist[strlist.length - 1]}"

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "www"
    switch event.type
      when "create"
        return [{
          entity: "Group"
          aspect: "\"#{event.data.name}\""
          collective: "new groups"
          verbed: "created"
          manner: ""
        }]
      when "update"
        attributes = []
        if event.data.name
          attributes.push({
            entity: "Group \"#{event.data.old_name}\""
            aspect: "name"
            collective: "changed groups"
            verbed: "changed"
            manner: "to \"#{event.data.name}\""
          })
        if event.data.logo
          attributes.push({
            entity: event.data.entity_name
            aspect: "logo"
            collective: "changed groups"
            verbed: "added"
            manner: ""
          })
        if event.data.remove_logo
          attributes.push({
            entity: event.data.entity_name
            aspect: "logo"
            collective: "changed groups"
            verbed: "removed"
            manner: ""
          })
        if event.data.member_changeset
          change_strings = []
          if event.data.member_changeset.add?.length > 0
            change_strings.push(
              comma_and(_.map(event.data.member_changeset.add, (m) -> m[0])) + " invited"
            )
          if event.data.member_changeset.remove?.length > 0
            change_strings.push(
              comma_and(_.map(event.data.member_changeset.remove, (m) -> m[0])) + " removed"
            )
          attributes.push({
            entity: event.data.entity_name
            aspect: "membership"
            collective: "changed groups"
            verbed: "changed"
            manner: change_strings.join("; ")
          })
        return attributes
      when "join"
        return [{
          entity: event.data.entity_name
          aspect: "invitation for #{event.data.user}"
          collective: "changed groups"
          verbed: "accepted"
          manner: ""
        }]
      when "decline"
        return [{
          entity: event.data.entity_name
          aspect: "invitation for #{event.data.user}"
          collective: "changed groups"
          verbed: "declined"
          manner: ""
        }]
    return null
}
