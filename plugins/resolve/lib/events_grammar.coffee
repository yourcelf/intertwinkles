logger = require("log4js").getLogger()

votes = {
  yes: "Strongly approve"
  weak_yes: "Approve with reservations"
  discuss: "Need more discussion"
  no: "Have concerns"
  block: "Block"
  abstain: "I have a conflict of interest"
}

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "resolve"
    switch event.type
      when "create"
        return [{
          entity: "Proposal"
          aspect: "\"#{event.data.entity_name}\""
          collective: "created proposals"
          verbed: "created"
          manner: ""
        }]
      when "visit"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "visits"
          verbed: "visited"
          manner: ""
        }]
      when "update"
        attributes = []
        if event.data.revision?
          attributes.push({
            entity: event.data.entity_name
            aspect: "proposal"
            collective: "changed proposals"
            verbed: "revised"
            manner: ""
          })
        if event.data.sharing?
          attributes.push({
            entity: event.data.entity_name
            aspect: "sharing settings"
            collective: "changed proposals"
            verbed: "changed"
            manner: ""
          })
        if event.data.passed?
          attributes.push({
            entity: event.data.entity_name
            aspect: "proposal"
            collective: "changed proposals"
            verbed: "finalized"
            manner: "proposal #{if event.data.passed then "passed" else "did not pass"}"
          })
        if event.data.reopened
          attributes.push({
            entity: event.data.entity_name
            aspect: "proposal"
            collective: "changed proposals"
            verbed: "reopened"
            manner: ""
          })
        return attributes
      when "append"
        return [{
          entity: event.data.entity_name
          aspect: "opinion"
          collective: "proposal responses"
          verbed: if event.data.is_new then "added" else "updated"
          manner: "#{votes[event.data.vote]}"
        }]
      when "trim"
        return [{
          entity: event.data.entity_name
          aspect: "opinion"
          collective: "proposal responses"
          verbed: "removed"
          manner: "(was \"#{votes[event.data.vote]}\")"
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
