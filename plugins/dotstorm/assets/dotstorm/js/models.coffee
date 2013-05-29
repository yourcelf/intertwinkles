Backbone.Model.prototype.idAttribute = '_id'

class ds.Idea extends Backbone.Model
  cleanTags: (commaStr) ->
    rawtags = commaStr.split(/,\s*/)
    clean = []
    for tag in rawtags
      if tag != ""
        clean.push($.trim(tag.replace(/[^-\w\s]/g, '')))
    return clean

class ds.IdeaList extends Backbone.Collection
  model: ds.Idea
  load: (data) =>
    if data?
      @add(data.ideas, {merge: true})
      @trigger "load", this
      for idea_json in data.ideas
        if idea_json?
          @get(idea_json._id).trigger "load"
    else
      @trigger "load", this

class ds.Dotstorm extends Backbone.Model
  defaults: { groups: [] }
  slugify: (name) -> return name.toLowerCase().replace(/[^a-z0-9_\.]/g, '-')

  load: (data) =>
    console.log "dotstorm load", data
    @set(data.dotstorm)
    @trigger "load", this

  validate: (attrs) ->
    if attrs.slug?.length < 4
      return "Name must be 4 or more characters."

  indexOfIdeaId: (idea_id, _list, _parent, _group_pos) =>
    groups = @get("groups") or []
    pos = i = -1
    for i in [0...groups.length]
      pos = _.indexOf groups[i].ideas, idea_id
      if pos != -1
        return [i, pos]
    return null

  #
  # Adding ideas
  #

  addIdea: (idea, options) =>
    @addIdeaId idea.id, options

  addIdeaId: (idea_id, options) =>
    unless @indexOfIdeaId(idea_id)?
      groups = @get("groups") or []
      groups.splice(0, 0, dotstorm_rearranger.create_group(idea_id))
      @set("groups", groups, options)

  #
  # Moving ideas within/between/into groups.
  # 
  # Takes 4 arguments:
  #   sourceGroupPos: the source group position (or null if the source is in
  #                   the trash).
  #   sourceIdeaPos: the position of the idea within the source group, or null
  #                  if the whole group is being moved.
  #   destGroupPos: the position of the group at the destination (or null if
  #                 the destination is the trash).
  #   destIdeaPos: the position of the idea within the group into which to
  #                interpolate the source idea(s); or null, if we intend to 
  #                drop the source idea(s) adjacent the destination group.
  #   offset: positional offset. 0 for left side, 1 for right side.
  
  move: (sourceGroupPos, sourceIdeaPos, destGroupPos, destIdeaPos, offset=0) =>
    groups = @get("groups")
    trash = @get("trash") or []
    dotstorm_rearranger.rearrange(groups, trash, [
      sourceGroupPos, sourceIdeaPos, destGroupPos, destIdeaPos, offset
    ])

    @set("groups", groups)
    @set("trash", trash)
    @trigger "change:ideas"
