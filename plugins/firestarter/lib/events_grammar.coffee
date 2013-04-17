logger = require("log4js").getLogger()

_ellipse = (string, length=30) ->
  if string.length > length
    return string.substring(0, length - 3) + "..."
  return string

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "firestarter"
    data = event.data or {}
    switch event.type
      when "create"
        return [{
          entity: "Firestarter"
          aspect: "\"#{data.entity_name or data.title}\""
          collective: "new firestarters"
          verbed: "created"
          manner: ""
        }]
      when "update"
        attributes = []
        if data.name?
          attributes.push {
            entity: "Firestarter"
            aspect: "the name"
            collective: "changed firestarters"
            verbed: "changed"
            manner: "from \"#{data.old_name}\" to \"#{data.name}\""
          }
        if data.prompt?
          attributes.push {
            entity: data.entity_name
            aspect: "the prompt"
            collective: "changed firestarters"
            verbed: "changed"
            manner: "to \"#{_ellipse(data.prompt or "")}\""
          }
        if data.sharing?
          attributes.push {
            entity: data.entity_name
            aspect: "the sharing settings"
            collective: "changed firestarters"
            verbed: "changed"
            manner: ""
          }
        return attributes
      when "append"
        if data.is_new
          return [{
            entity: data.entity_name
            aspect: "a response"
            collective: "added responses"
            verbed: "added"
            manner: _ellipse(data.text)
          }]
        else
          return [{
            entity: data.entity_name
            aspect: "a response"
            collective: "edited responses"
            verbed: "edited"
            manner: _ellipse(data.text or "")
          }]
      when "trim"
        return [{
            entity: data.entity_name
            aspect: "a response"
            collective: "removed responses"
            verbed: "removed"
            manner: _ellipse(data.text or "")
        }]
      when "visit"
        return [{
          entity: data.entity_name
          aspect: "the firestarter"
          collective: "visited firestarters"
          verbed: "visited"
          manner: ""
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
