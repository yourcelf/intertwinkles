expect  = require 'expect.js'
_       = require 'underscore'
async   = require 'async'
config  = require '../../../test/test_config'
common  = require '../../../test/common'
logger  = require('log4js').getLogger("test-resolve")
api_methods = require("../../../lib/api_methods")(config)
www_schema = require('../../../lib/schema').load(config)
resolve_schema = require("../lib/schema").load(config)
resolve = require("../lib/resolve")(config)

describe "resolve", ->
  before (done) ->
    common.startUp (server) =>
      @server = server

      # Establish a session
      @session = {}
      @session2 = {}
      async.series [
        (done) =>
          common.stubBrowserID({email: "one@mockmyid.com"})
          www_schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) =>
            @user = doc
            done(err)
        (done) =>
          api_methods.authenticate(@session, "assertion", done)

        (done) =>
          common.stubBrowserID({email: "two@mockmyid.com"})
          www_schema.User.findOne {email: "two@mockmyid.com"}, (err, doc) =>
            @user2 = doc
            done(err)

        (done) =>
          api_methods.authenticate(@session2, "assertion", done)

        (done) =>
          # Build a proposal to work with.
          new resolve_schema.Proposal({
            revisions: [{
              user_id: @user.id
              name: "One"
              text: "Test proposal?"
            }]
          }).save (err, doc) =>
            @proposal = doc
            done(err)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "Posts events", (done) ->
    resolve.post_event @session, @proposal, {type: "visit"}, 0, (err, event) =>
      expect(err).to.be(null)
      expect(event.application).to.be("resolve")
      expect(event.entity).to.be(@proposal.id)
      www_schema.Event.findOne {entity: @proposal.id}, (err, doc) =>
        expect(err).to.be(null)
        expect(doc.id).to.be(event.id)
        expect(doc.entity).to.be(event.entity)
        expect(doc.group).to.be(@proposal.sharing.group_id)
        expect(doc.anon_id).to.be(@session.anon_id)
        
        terms = api_methods.get_event_grammar(doc)
        expect(terms.length).to.be(1)
        expect(terms[0].entity).to.be(@proposal.title)
        expect(terms[0].aspect).to.be("")
        expect(terms[0].collective).to.be("visits")
        expect(terms[0].verbed).to.be("visited")
        expect(terms[0].manner).to.be("")

        done()

  it "Posts search indices", (done) ->
    resolve.post_search_index @proposal, (err, si) =>
      expect(err).to.be(null)
      expect(si).to.not.be(null)
      expect(si.entity).to.be(@proposal.id)
      expect(si.application).to.be("resolve")
      www_schema.SearchIndex.findOne {entity: @proposal.id}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc.id).to.be(si.id)
        done()
 
  it "Posts proposal revision twinkles", (done) ->
    resolve.post_twinkle @session, @proposal.id, @proposal.revisions[0].id, (err, tw) =>
      expect(err).to.be(null)
      expect(tw).to.not.be(null)
      expect(tw.sender.toString()).to.be(@session.auth.user_id)
      expect(tw.url).to.be(@proposal.url)
      expect(tw.absolute_url).to.be(@proposal.absolute_url)
      @twinkle_to_remove = tw
      done()

  it "Removes a twinkle", (done) ->
    resolve.remove_twinkle @session, @twinkle_to_remove.id, @proposal.id, (err, tw, doc) =>
      expect(err).to.be(null)
      expect(tw).to.not.be(null)
      expect(tw.id).to.be(@twinkle_to_remove.id)
      expect(doc.id).to.be(@proposal.id)
      www_schema.Twinkle.findOne {_id: @twinkle_to_remove.id}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.be(null)
        done()

  it "Creates a proposal", (done) ->
    group = _.find @session.groups, (g) -> g.name == "Two Members"
    resolve.create_proposal @session, {
      proposal: {
        proposal: "This is my proposal."
        sharing: { group_id: group.id }
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.revisions[0].text).to.be("This is my proposal.")
      expect(proposal.revisions[0].user_id).to.be(@session.auth.user_id)
      expect(proposal.url).to.be("/p/#{proposal.id}/")
      expect(proposal.absolute_url).to.be(
        "http://localhost:#{config.port}/resolve/p/#{proposal.id}/"
      )
      expect(event.type).to.be("create")
      expect(event.absolute_url).to.be(proposal.absolute_url)
      expect(event.application).to.be("resolve")
      expect(si.entity.toString()).to.be(proposal.id)
      expect(si.absolute_url).to.be(proposal.absolute_url)
      expect(notices.length).to.be(_.size(group.members))

      for notice in notices
        expect(notice.url).to.be(proposal.url)
        expect(notice.absolute_url).to.be(proposal.absolute_url)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Proposal"
        aspect: "\"#{proposal.title}\""
        collective: 'created proposals'
        verbed: 'created'
        manner: ""
      })

      @proposal_with_notices = proposal
      www_schema.Notification.find {entity: @proposal_with_notices.id}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.length).to.be(2)
        done()

  it "Updates notifications based on resolution", (done) ->
    #general test of update notifications method.
    @proposal_with_notices.resolved = new Date()
    @proposal_with_notices.save (err, doc) =>
      www_schema.Notification.find {entity: doc.id}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.length).to.be(2)
        resolve.update_notifications @session, doc, (err, notifications) =>
          expect(notifications.length).to.be(2)
          expect(_.all(n.cleared for n in notifications)).to.be(true)
          www_schema.Notification.find {entity: doc.id, cleared: false}, (err, docs) =>
            expect(docs.length).to.be(0)
            done()

  it "Updates a proposal", (done) ->
    expect(@proposal_with_notices.resolved).to.not.be(null)
    expect(@proposal_with_notices.sharing.group_id).to.not.be(null)
    resolve.update_proposal @session, {
      proposal: { reopened: true, _id: @proposal_with_notices.id }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.id).to.be(@proposal_with_notices.id)
      expect(proposal.resolved).to.be(null)

      expect(event.group.toString()).to.be(
        @proposal_with_notices.sharing.group_id.toString()
      )
      expect(event.url).to.be(proposal.url)
      expect(event.absolute_url).to.be(proposal.absolute_url)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: @proposal_with_notices.title
        aspect: "proposal"
        collective: "changed proposals"
        verbed: "reopened"
        manner: ""
      })

      for notice in notices
        expect(notice.url).to.be(proposal.url)
        expect(notice.absolute_url).to.be(proposal.absolute_url)
        expect(notice.formats.web).to.not.be(undefined)
        expect(notice.toObject().formats.email).to.be(undefined)

      expect(err).to.be(null)
      @proposal_with_notices = proposal

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "proposal"
        collective: 'changed proposals'
        verbed: 'reopened'
        manner: ""
      })

      done()

  it "Updates notifications based on votes", (done) ->
    prop = @proposal_with_notices
    expect(prop.resolved).to.be(null)
    user_id = prop.revisions[0].user_id
    prop.opinions.push {
      user_id: user_id
      name: @session.users[user_id].name
      revisions: [{
        vote: "weak_yes"
        text: "Okie"
      }]
    }
    prop.save (err, doc) =>
      resolve.update_notifications @session, doc, (err, notifications) =>
        expect(err).to.be(null)
        expect(notifications?.length).to.be(3)
        cleared = 0
        uncleared = 0
        for notice in notifications
          if notice.cleared
            cleared += 1
          else
            uncleared += 1
            expect(notice.recipient.toString()).to.not.eql(user_id.toString())
          expect(notice.formats.web).to.not.be(undefined)
          expect(notice.toObject().formats.email).to.be(undefined)
        expect(cleared).to.be(2)
        expect(uncleared).to.be(1)
        doc.opinions.pop()
        doc.save  (err, doc) =>
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          resolve.update_notifications @session, doc, (err, notifications) =>
            expect(err).to.be(null)
            expect(notifications.length).to.be(3)
            cleared = 0
            uncleared = 0
            for notice in notifications
              if notice.cleared
                cleared += 1
                expect(notice.recipient.toString()).to.not.eql(user_id.toString())
              else
                uncleared += 1
            expect(cleared).to.be(1)
            expect(uncleared).to.be(2)
            done()

  it "Opinion: error out", (done) ->
    resolve.add_opinion @session, {
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "Oh yeah"
        vote: "weak_yes"
      }
    }, (err, proposal) =>
      expect(proposal).to.be(undefined)
      expect(err).to.not.be(null)
      done()

  it "Adds an opinion as self", (done) ->
    start_length = @proposal.opinions.length
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "Super!!!"
        vote: "weak_yes"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.be(@session.auth.user_id)
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Super!!!")
      expect(proposal.opinions[start_length].revisions[0].vote).to.be("weak_yes")
    
      expect(event?.type).to.be("append")
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.via_user).to.be(undefined)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "Approve with reservations"
      })

      expect(si.text.indexOf("Super!!!")).to.not.be(-1)
      expect(notices.length).to.be(0)
      # TODO: Fix this data blob to be less silly.
      @proposal = proposal
      done()

  it "Adds an opinion as group member", (done) ->
    start_length = @proposal.opinions.length
    www_schema.User.findOne {email: "two@mockmyid.com" }, (err, user) =>
      expect(err).to.be(null)
      expect(user).to.not.be(null)
      # @session belongs to one@mockmyid.com.
      resolve.add_opinion @session, {
        proposal: {_id: @proposal._id}
        opinion: {
          user_id: user._id
          name: user.name
          text: "Far out"
          vote: "no"
        }
      }, (err, proposal, event, si, notices) =>
        expect(err).to.be(null)
        expect(proposal).to.not.be(null)
        expect(proposal.opinions.length).to.be(start_length + 1)
        expect(proposal.opinions[start_length].user_id).to.eql(user.id)
        expect(proposal.opinions[start_length].revisions[0].text).to.be("Far out")

        expect(event.user.toString()).to.be(user.id)
        expect(event.via_user.toString()).to.be(@session.auth.user_id)
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: proposal.title
          aspect: "opinion"
          collective: 'proposal responses'
          verbed: 'added'
          manner: "Have concerns"
        })

        @proposal = proposal
        done()

  it "Adds an opinion for anonymous", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: undefined
        name: "Anonymouse"
        text: "Fur out"
        vote: "no"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.eql(null)
      expect(proposal.opinions[start_length].name).to.be("Anonymouse")
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Fur out")

      expect(event.user).to.be(undefined)
      expect(event.via_user.toString()).to.be(@session.auth.user_id)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "Have concerns"
      })
      @proposal = proposal
      done()

  it "Adds an opinion for group member, as anonymous", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion {}, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: undefined
        name: "One"
        text: "Four out"
        vote: "abstain"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.eql(null)
      expect(proposal.opinions[start_length].name).to.be("One")
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Four out")

      expect(event.user).to.be(undefined)
      expect(event.via_user).to.be(undefined)
      expect(event.data.user.name).to.be("One")

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "I have a conflict of interest"
      })
      @proposal = proposal
      done()

  it "Adds a second opinion as self", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "On second thought..."
        vote: "abstain"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length) # no increase
      op = _.find proposal.opinions, (o) => o.user_id == @session.auth.user_id
      expect(op?.revisions.length).to.be(2)
      expect(op.revisions[0].text).to.be("On second thought...")
      expect(op.revisions[1].text).to.be("Super!!!")
      @opinion_to_remove = op
      @proposal = proposal
      done()

  it "Removes an opinion", (done) ->
    start_length = @proposal.opinions.length
    resolve.remove_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {_id: @opinion_to_remove._id}
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length - 1)
      expect(_.find proposal.opinions, (o) =>
        o.user_id == @opinion_to_remove.user_id
      ).to.be(undefined)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'removed'
        manner: "(was \"I have a conflict of interest\")"
      })

      done()

  it "Adds resolution notices for passage", (done) ->
    resolve.update_proposal @session, {
      proposal: {
        _id: @proposal_with_notices.id
        passed: true
        message: "This is why it passed"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.resolutions.length).to.be(2)
      res = proposal.resolutions[0]
      expect(res.is_resolved).to.be(true)
      expect(res.passed).to.be(true)
      expect(res.message).to.be("This is why it passed")
      expect(res.user_id).to.be(@session.auth.user_id)
      expect(res.name).to.be(undefined)
      done()

  it "Adds resolution notices for reopening", (done) ->
    resolve.update_proposal @session, {
      proposal: {
        _id: @proposal_with_notices.id
        reopened: true
        message: "This is why it reopened"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.resolved).to.be(null)
      expect(proposal.resolutions.length).to.be(3)
      res = proposal.resolutions[0]
      expect(res.is_resolved).to.be(false)
      expect(res.passed).to.be(null)
      expect(res.message).to.be("This is why it reopened")
      expect(res.user_id).to.be(@session.auth.user_id)
      expect(res.name).to.be(undefined)
      done()

  it "puts a proposal in the trash", (done) ->
    proposal = @proposal_with_notices
    session = @session
    www_schema.Notification.find {
      entity: proposal.id
      cleared: false
    }, (err, docs) ->
      expect(err).to.be(null)
      expect(docs).to.not.be(null)
      expect(docs.length > 0).to.be(true)
      api_methods.trash_entity session, {
        application: "resolve"
        entity: proposal.id
        group: proposal.sharing.group_id
        trash: true
      }, (err, event, si, handler_res) ->
        expect(err).to.be(null)
        expect(event).to.not.be(null)
        expect(si).to.not.be(null)
        expect(handler_res).to.not.be(null)

        expect(si.trash).to.be(true)

        expect(event.type).to.be("trash")
        expect(event.absolute_url).to.be(proposal.absolute_url)
        expect(event.url).to.be(proposal.url)
        expect(event.entity).to.be(proposal.id)
        expect(event.application).to.be("resolve")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: proposal.title
          aspect: ""
          collective: "removals"
          verbed: "moved to trash"
          manner: ""
        })

        www_schema.Notification.find {
          entity: proposal.id
          cleared: false
        }, (err, docs) ->
          expect(err).to.be(null)
          expect(docs?.length).to.be(0)
          done()

  it "removes a proposal from teh trash", (done) ->
    proposal = @proposal_with_notices
    session = @session
    www_schema.Notification.find {
      entity: proposal.id
      cleared: false
    }, (err, docs) ->
      expect(err).to.be(null)
      expect(docs).to.not.be(null)
      expect(docs.length).to.be(0)
      api_methods.trash_entity session, {
        application: "resolve"
        entity: proposal.id
        group: proposal.sharing.group_id
        trash: false
      }, (err, event, si, handler_res) ->
        expect(err).to.be(null)
        expect(event).to.not.be(null)
        expect(si).to.not.be(null)
        expect(handler_res).to.not.be(null)

        expect(si.trash).to.be(false)

        expect(event.type).to.be("untrash")
        expect(event.absolute_url).to.be(proposal.absolute_url)
        expect(event.url).to.be(proposal.url)
        expect(event.entity).to.be(proposal.id)
        expect(event.application).to.be("resolve")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: proposal.title
          aspect: ""
          collective: "removals"
          verbed: "restored from trash"
          manner: ""
        })

        www_schema.Notification.find {
          entity: proposal.id
          cleared: false
        }, (err, docs) ->
          expect(err).to.be(null)
          expect(docs).to.not.be(null)
          expect(docs.length > 0).to.be(true)
          done()

  it "requests deletion of a proposal", (done) ->
    proposal = @proposal_with_notices
    session = @session
    session2 = @session2
    dr = null

    async.series [
      # First, add a couple of responses so that we have multiple authors
      (done) ->
        resolve.add_opinion session, {
          proposal: {_id: proposal._id}
          opinion: {
            user_id: session.auth.user_id
            name: session.users[session.auth.user_id].name
            text: "My opinion is..."
            vote: "abstain"
          }
        }, (err) ->
          done(err)

      (done) ->
        resolve.add_opinion session2, {
          proposal: {_id: proposal._id}
          opinion: {
            user_id: session2.auth.user_id
            name: session2.users[session2.auth.user_id].name
            text: "My thinking is..."
            vote: "abstain"
          }
        }, (err, proposal) ->
          done(err)

      # Now try deleting -- this should queue, and not delete outright.
      (done) ->
        api_methods.request_deletion session, {
          application: "resolve"
          entity: proposal.id
          group: proposal.sharing.group_id
          url: proposal.url
          title: proposal.title
        }, (err, thedr, trashing, event, notices) ->
          dr = thedr

          expect(err).to.be(null)
          expect(dr).to.not.be(null)
          expect(dr.url).to.be("/deletionrequest/#{dr.id}/")
          expect(dr.absolute_url).to.be("#{config.api_url}/deletionrequest/#{dr.id}/")
          expect(trashing).to.not.be(null)
          expect(event).to.not.be(null)
          expect(notices).to.not.be(null)
          expect(notices.length).to.be(1)
          expect(notices[0].url).to.be(dr.url)
          expect(notices[0].absolute_url).to.be(dr.absolute_url)


          expect(event.type).to.be("deletion")
          expect(event.url).to.be(dr.entity_url)
          expect(event.absolute_url).to.be(proposal.absolute_url)
          expect(event.entity).to.be(proposal.id)
          expect(event.application).to.be('resolve')
          terms = api_methods.get_event_grammar(event)
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: proposal.title
            aspect: ""
            collective: "removals"
            verbed: "deletion requested"
            manner: ""
          })

          [trash_event, si, handler_res] = trashing
          expect(trash_event).to.not.be(null)
          expect(si).to.not.be(null)
          expect(handler_res).to.not.be(null)
          expect(si.trash).to.be(true)

          [proposal, prop_notices] = handler_res
          expect(proposal).to.not.be(null)
          expect(prop_notices).to.not.be(null)
          expect(proposal.trash).to.be(true)

          expect(dr.application).to.be("resolve")
          expect(dr.url).to.be("/deletionrequest/#{dr.id}/")
          expect(dr.absolute_url).to.be("#{config.api_url}/deletionrequest/#{dr.id}/")
          expect(dr.entity).to.be(proposal.id)
          expect(dr.entity_url).to.be(proposal.url)
          expect(dr.absolute_entity_url).to.be(proposal.absolute_url)
          expect(dr.title).to.be(proposal.title)
          expect(dr.confirmers.length).to.be(1)
          expect(dr.confirmers[0].toString()).to.eql(session.auth.user_id)

          done()

      # Cancel deletion.
      (done) ->
        api_methods.cancel_deletion session, dr._id, (err, event, untrashing) ->
          common.no_err_args([err, event, untrashing])

          expect(event.type).to.be("undeletion")
          expect(event.url).to.be(proposal.url)
          expect(event.absolute_url).to.be(proposal.absolute_url)
          expect(event.entity).to.be(proposal.id)
          expect(event.application).to.be("resolve")
          terms = api_methods.get_event_grammar(event)
          expect(terms.length).to.be(1)
          expect(terms[0]).to.eql({
            entity: proposal.title
            aspect: ""
            collective: "removals"
            verbed: "deletion cancelled"
            manner: ""
          })

          [untrash_event, si, handler_res] = untrashing
          common.no_err_args([null, untrash_event, si, handler_res])
          expect(si.trash).to.be(false)

          [proposal, notices] = handler_res
          expect(proposal).to.not.be(null)
          expect(notices).to.not.be(null)
          expect(proposal.trash).to.be(false)

          www_schema.DeletionRequest.find {entity: proposal.id}, (err, docs) ->
            expect(err).to.be(null)
            expect(docs.length).to.be(0)
            www_schema.Notification.find {
                entity: proposal.id, type: "deletion", cleared: false
            }, (err, docs) ->
              expect(err).to.be(null)
              expect(docs.length).to.be(0)
              done()

      # Delete successfully with confirmation
      (done) ->
        api_methods.request_deletion session, {
          application: "resolve"
          entity: proposal.id
          group: proposal.sharing.group_id
          url: proposal.url
          title: proposal.title
        }, (err, thedr, trashing, event, notices) ->
          expect(err).to.be(null)
          expect(thedr).to.not.be(null)

          api_methods.confirm_deletion session2, thedr.id, (err, notices) ->
            # Second confirmation; should be no notices.
            expect(err).to.be(null)
            expect(notices).to.be(undefined)

            entity = proposal._id
            async.parallel [
              (done) ->
                resolve_schema.Proposal.findOne {
                  _id: entity
                }, (err, doc) ->
                  expect(err).to.be(null)
                  expect(doc).to.be(null)
                  done()
              (done) ->
                www_schema.Event.find {entity}, (err, edocs) ->
                  expect(err).to.be(null)
                  expect(edocs.length).to.be(0)
                  done()
              (done) ->
                www_schema.SearchIndex.find {entity}, (err, sidocs) ->
                  expect(err).to.be(null)
                  expect(sidocs.length).to.be(0)
                  done()
              (done) ->
                www_schema.Notification.find {entity: entity}, (err, ndocs) ->
                  expect(err).to.be(null)
                  expect(ndocs.length).to.be(0)
                  done()
              (done) ->
                www_schema.Twinkle.find {entity}, (err, tdocs) ->
                  expect(err).to.be(null)
                  expect(tdocs.length).to.be(0)
                  done()
            ], (err) ->
              done(err)

    ], (err) ->
      done(err)

  it "Deletes immediately if requested by the only involved user", (done) ->
    session = @session
    group = _.find session.groups, (g) -> g.name == "Two Members"
    resolve.create_proposal  session, {
      proposal: {
        proposal: "Just one person."
        sharing: {group_id: group.id}
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      api_methods.request_deletion session, {
        application: "resolve"
        entity: proposal.id
        group: proposal.sharing.group_id
        url: proposal.url
        title: proposal.title
      }, (err, args) ->
        expect(err).to.be(null)
        expect(args).to.be(undefined)
        resolve_schema.Proposal.findOne {_id: proposal.id}, (err, doc) ->
          expect(err).to.be(null)
          expect(doc).to.be(null)
          done()

  it "Handles deferred deletion", (done) ->
    [session, session2] = [@session, @session2]
    group = _.find session.groups, (g) -> g.name == "Two Members"
    async.waterfall [
      # Create a thing edited by two people.
      (done) ->
        resolve.create_proposal session, {
          proposal: {
            proposal: "This is my proposal."
            sharing: { group_id: group._id }
          }
        }, (err, proposal, event, si, notices) =>
          common.no_err_args([err, proposal, event, si, notices])
          resolve.update_proposal session2, {
            proposal: {
              _id: proposal._id
              proposal: "This is my better proposal."
            }
          }, (err, proposal, event, si, notices) =>
            common.no_err_args([err, proposal, event, si, notices])
            done(null, proposal)

      # Create a deletion request
      (proposal, done) ->
        api_methods.request_deletion session, {
          group: proposal.sharing.group_id
          application: "resolve"
          entity: proposal._id
          url: proposal.url
          title: proposal.title
        }, (err, dr, trashing, event, notices) ->
          common.no_err_args([err, dr, trashing, event, notices])
          done(null, dr)

      # Try running deletions -- should not impact dr.
      (dr, done) ->
        www_schema.DeletionRequest.findOne {_id: dr._id}, (err, dr) ->
          expect(err).to.be(null)
          expect(dr).to.not.be(null)
          api_methods.process_deletions (err, count) ->
            expect(err).to.be(null)
            expect(count).to.be(0)
            www_schema.DeletionRequest.findOne {_id: dr._id}, (err, dr) ->
              expect(err).to.be(null)
              expect(dr).to.not.be(null)
              resolve_schema.Proposal.findOne {_id: dr.entity}, (err, doc) ->
                expect(err).to.be(null)
                expect(doc).to.not.be(null)
                expect(doc).to.not.be(undefined)
                done(null, dr)

      # Back-date the deletion request, and run deletions. Should delete.
      (dr, done) ->
        dr.start_date = new Date(new Date().getTime() - 1000 * 60 * 60 * 24 * 3)
        dr.end_date = new Date()
        dr.save (err, dr) ->
          expect(err).to.be(null)
          api_methods.process_deletions (err, count) ->
            expect(err).to.be(null)
            expect(count).to.be(1)
            www_schema.DeletionRequest.findOne {_id: dr._id}, (err, deleted) ->
              expect(err).to.be(null)
              expect(deleted).to.be(null)
              resolve_schema.Proposal.findOne {_id: dr.entity}, (err, doc) ->
                expect(err).to.be(null)
                expect(doc).to.be(null)
                done()

    ], done

        
        


