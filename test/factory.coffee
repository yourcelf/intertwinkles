_     = require 'underscore'
async = require 'async'
logger = require("log4js").getLogger()
events = require "events"
mongoose = require("mongoose")

#
# Create factory based on given config.
#
module.exports.run = (config, done) ->
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  www_schema = require("../lib/schema").load(config)
  res_schema = require("../plugins/resolve/lib/schema").load(config)

  day_zero = new Date().getTime() - (1000 * 60 * 60 * 24) * 7
  day = (plus_days) ->
    return new Date(day_zero + plus_days * (1000 * 60 * 60 * 24))

  cache = {}

  create_user = (attrs, done) ->
    [email, name] = attrs
    cache.users ?= {}
    logger.info("Creating user #{email}, #{name}")
    www_schema.User.findOne {email: email}, (err, doc) ->
      throw err if err?
      if not doc
        new www_schema.User({email: email, name: name, joined: day(0)}).save (err, doc) ->
          throw(err) if err
          cache.users[name] = doc
          done(null, doc)
          logger.info(" done.")
      else
        cache.users[name] = doc
        logger.info(" already exists.")
        done(null, doc)

  create_group = (user, attributes, done) ->
    logger.info("Creating group #{attributes.name}")
    cache.groups or= {}
    www_schema.Group.findOne {name: attributes.name}, (err, doc) ->
      throw err if err?
      if not doc
        members = [{
          voting: true
          user: cache.users[user].id
          joined: attributes.on
        }]
        new www_schema.Group({
          created: attributes.on
          modified: attributes.on
          members: members
          name: attributes.name
          slug: attributes.name.toLowerCase().replace(" ", "-")
        }).save (err, doc) ->
          throw err if err?
          cache.groups[attributes.name] = doc
          done(null, doc)
          logger.info(" done.")
      else
        cache.groups[attributes.name] = doc
        logger.info(" already exists.")
        done(null, doc)

  invite_users = (user, attributes, done) ->
    group = cache.groups[attributes.group]
    group.invited_members ?= []
    for name in attributes.invitees
      unless _.find(group.invited_members, (a) -> a.id == cache.users[name].id)
        logger.info "Inviting #{name} [#{cache.users[name].id}] to #{group.name}"
        group.invited_members.push {
          invited_by: cache.users[user].id
          invited_on: attributes.on
          voting: true
          user: cache.users[name].id
        }
    group.save (err, doc) ->
      if err?
        logger.error("#{name} [#{cache.users[name].id}] #{attributes.group} create invite failed")
        throw err
      done(err, doc)

  accept_invite = (name, attributes, done) ->
    logger.info("Accepting invite for #{name} to #{attributes.group}")
    group = cache.groups[attributes.group]
    inv = null
    for invitation, i in group.invited_members
      if cache.users[name].id == invitation.user.toString()
        inv = group.invited_members.splice(i, 1)[0]
        break
    unless _.find(group.members, (a) -> a.id == cache.users[name].id)
      group.members.push({
        invited_by: inv?.invited_by
        invited_on: inv?.invited_on
        role: inv?.role
        voting: inv?.voting
        user: cache.users[name].id
      })
    group.save (err, doc) ->
      if err?
        logger.error "#{name} [#{cache.users[name].id}] #{attributes.group} accept invite failed"
        throw err
      logger.info(" #{name} #{attributes.group} invite accepted.")
      done(err, doc)

  create_event = (name, attributes, done) ->
    logger.info "Creating event: #{attributes.type} #{attributes.application} #{attributes.entity}"
    attrs = _.extend {}, attributes
    attrs.user = cache.users[name].id
    attrs.via_user = cache.users[attrs.via_user].id if attrs.via_user?
    attrs.group = cache.groups[attrs.group].id if attrs.group?
    new www_schema.Event(attrs).save (err, doc) ->
      throw err if err?
      return done(null, doc) if doc?

  create_proposal = (name, attributes, done) ->
    # Since there's no simple "natural key" (e.g. a name or slug) for a
    # proposal, use an included 'cache' value as the key.
    logger.info("Creating proposal #{attributes.text} by #{name} for #{attributes.group}")

    if cache.proposals?[attributes.cache]?
      logger.info(" already exists.")
      return done(null, cache.proposals[cache])
    new res_schema.Proposal({
      resolved: null
      revisions: [{
        user_id: cache.users[name].id
        name: name
        date: attributes.on
        text: attributes.text
      }]
      sharing: {
        group_id: if attributes.group then cache.groups[attributes.group].id else undefined
      }
    }).save (err, doc) ->
      throw err if err?
      logger.info(" done.")
      cache.proposals ?= {}
      cache.proposals[attributes.cache] = doc

      create_event(name, {
        application: "resolve"
        type: "create"
        entity_url: "/resolve/p/#{doc._id}"
        entity: doc._id
        user: cache.users[name].id
        date: attributes.on
        data: {
          title: doc.title
          action: "create"
          proposal: doc.revisions[0]
        }
      }, (err) -> done(err, doc))

  visit_proposal = (name, proposal, date, done) ->
    create_event name, {
        application: "resolve"
        type: "visit"
        entity_url: "/resolve/p/#{proposal._id}"
        entity: proposal._id
        user: cache.users[name]?.id
        date: date
        data: {
          name: name
        }
    }, done

  revise_proposal = (name, proposal, attributes, done) ->
    logger.info("#{name} Revising proposal #{proposal.revisions[0].text}")
    proposal.revisions.unshift({
      user_id: cache.users[name]?.id
      name: name
      date: attributes.date
      text: attributes.text
    })
    visit_proposal name, proposal, attributes.date, (err) ->
      proposal.save (err, doc) ->
        done(err, doc)

  create_opinion = (name, proposal, attributes, done) ->
    logger.info "Creating opinion on \"#{proposal.revisions[0].text}\" for #{name}"
    opa = _.find proposal.opinions, (o) ->
      o.user_id == cache.users[name]?.id and o.name == name
    unless opa
      opa = {
        user_id: cache.users[name]?.id
        name: name
        revisions: []
      }
      proposal.opinions.unshift(opa)
      opa = proposal.opinions[0]

    opa.revisions.push {
      vote: attributes.vote
      text: attributes.text
      date: attributes.date
    }
    # Save the proposal, and also add a visit.
    visit_proposal name, proposal, attributes.date, (err) ->
      proposal.save (err, doc) ->
        throw err if err?
        create_event name, {
          application: "resolve"
          type: "append"
          entity_url: "/resolve/p/#{doc._id}"
          entity: doc._id
          user: cache.users[name]?.id
          date: attributes.date
          data: {
            name: name
            opinion: {
              user_id: cache.users[name]?.id
              name: name
              revisions: opa.revisions
            }
          }
        }, done

  #
  # Execute the factory.  Run a time series to create data.
  #

  async.waterfall [
    (done) ->
      # Create user accounts
      async.mapSeries [
          ["one@mockmyid.com", "Oner"]
          ["two@mockmyid.com", "Toosie"]
          ["three@mockmyid.com", "Trey"]
          ["four@mockmyid.com", "Flora"]
          ["five@mockmyid.com", "Penta"]
          ["six@mockmyid.com", "Hexie"]
          ["seven@mockmyid.com", "Septer"]
          ["eight@mockmyid.com", "Octavia"]
          ["nine@mockmyid.com", "Nonce"]
          ["ten@mockmyid.com", "Deca"]
          ["eleven@mockmyid.com", "Elve"]
          ["twelve@mockmyid.com", "Dodec"]
          ["thirteen@mockmyid.com", "Thursten"]
          ["fourteen@mockmyid.com", "Florentine"]
          ["fifteen@mockmyid.com", "Fliff"]
          ["sixteen@mockmyid.com", "Siggs"]
        ], create_user, (err, results) -> done(err)

    (done) ->
      create_group "Oner", {name: "Digits", on: day(1)}, (err, res) ->
        done(err)

    (done) -> invite_users "Oner", {
          group: "Digits",
          invitees: ["Toosie", "Trey", "Flora", "Penta", "Hexie", "Septer",
            "Octavia", "Nonce", "Deca", "Elve"],
          on: day(1.1)
        }, (err, res) ->
          done(err)

    (done) ->
      async.mapSeries([
          "Toosie", "Trey", "Flora", "Penta", "Hexie", "Septer", "Octavia",
          "Nonce", "Deca"
        ], (name, done) ->
          accept_invite(name, {group: "Digits", on: day(2)}, done)
        , (err, res) ->
          done(err)
      )

    (done) -> create_proposal "Trey", {
        group: "Digits", cache: "one", text: "Tea", on: day(2.2)
      }, (err, doc) ->
        done(err, doc)

    (prop, done) -> visit_proposal "Trey", prop, day(2.5), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Flora", prop, day(2.6), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Penta", prop, day(2.61), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Flora", prop, day(2.62), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Hexie", prop, day(3), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Septer", prop, day(3), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Trey", prop, day(3.1), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Trey", prop, day(3.2), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Trey", prop, day(3.2), (err) -> done(err, prop)
    (prop, done) -> visit_proposal "Octavia", prop, day(4.2), (err) -> done(err, prop)

    (prop, done) -> create_opinion "Hexie", prop, {
        date: day(3.0), vote: "yes", text: "Sounds good"
      }, (err) -> done(err, prop)

    (prop, done) -> create_opinion "Trey", prop, {
        date: day(3.1), vote: "yes", text: "Sounds good"
      }, (err) -> done(err, prop)

    (prop, done) -> revise_proposal "Octavia", prop, {
        date: day(3.15), text: "Tea, Earl grey"
      }, (err, doc) ->
        done(err, doc)

    (prop, done) -> create_opinion "Trey", prop, {
        date: day(3.2), vote: "yes", text: "Sounds good"
      }, (err) -> done(err, prop)

    (prop, done) -> create_opinion "Flora", prop, {
        date: day(3.5), vote: "yes", text: "Sounds good"
      }, (err) -> done(err, prop)
    (prop, done) -> create_opinion "Flora", prop, {
        date: day(3.62), vote: "yes", text: "Sounds good"
      }, (err) -> done(err, prop)


  ], (err) ->
    throw err if err?
    db.disconnect(done or (->))
