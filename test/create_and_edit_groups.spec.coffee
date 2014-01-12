fs      = require 'fs'
expect  = require 'expect.js'
config  = require './test_config'
common  = require './common'
www_schema = require("../lib/schema").load(config)


describe "creates and edits groups", ->
  browser = null
  server = null

  before (done) ->
    common.startUp (theServer) =>
      server = theServer
      common.fetchBrowser (theBrowser) =>
        browser = theBrowser
        done()

  after (done) ->
    browser.quit().then -> common.shutDown(server, done)

  it "creates group", (done) ->
    test_logo = __dirname + "/logo.png"
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      expect(err).to.be(null)
      browser.get("http://localhost:#{config.port}/groups/new")
      browser.byCss("h1").getText().then (text) ->
        expect(text).to.be("New group")
      browser.byCss("[name=name]").sendKeys("Affinito")
      browser.byCss("#id_logo").sendKeys(test_logo)
      browser.byCss("#add_email").sendKeys("two@mockmyid.com")
      browser.byCss("a.add-new-invitee").click()
      browser.byCss(".newinvitee").then (el) -> expect(el?).to.be(true)
      browser.byCss("form.form-horizontal").submit()

      # Verify the group was created correctly
      browser.wait ->
        browser.byCsss(".membership-list li").then (lis) ->
          return lis.length == 1
      browser.byCss("#invited_members a").getText().then (text) ->
        expect(text).to.be("1 invited members")
      browser.byCss("h1").getText().then (text) ->
        expect(text).to.be("Affinito")
      # should raise error if el doesn't exist.
      browser.byCss("h1 img").then ->
        www_schema.Group.findOne {name: "Affinito"}, (err, doc) ->
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          expect(doc.name).to.be("Affinito")
          expect(doc.slug).to.be("affinito")
          expect(doc.logo.full).to.not.be(null)
          expect(fs.existsSync(__dirname + '/../uploads/' + doc.logo.full)).to.be(true)
          expect(doc.logo.thumb).to.not.be(null)
          expect(fs.existsSync(__dirname + '/../uploads/' + doc.logo.thumb)).to.be(true)
          expect(doc.members.length).to.be(1)
          expect(doc.invited_members.length).to.be(1)
          expect(!!doc.disabled).to.be(false)
          done()

  it "edits the group", (done) ->
    # Edit the group -- remove logo, change name, invite another
    common.stubAuthenticate browser, "one@mockmyid.com", (err) ->
      browser.get("http://localhost:#{config.port}/groups/show/affinito")
      browser.byCss("[title='Edit group']").click()
      browser.byCss(".remove-logo").click()
      browser.byCss("#id_name").sendKeys("2")
      browser.byCss("#add_email").sendKeys("three@mockmyid.com")
      browser.byCss("form.form-horizontal").submit()

      # Verify that it was edited correctly
      browser.wait ->
        browser.byCsss(".membership-list li").then (lis) ->
          return lis.length == 1
      browser.byCss("#invited_members a").getText().then (text) ->
        expect(text).to.be("2 invited members")
      browser.byCss("h1").getText().then (text) ->
        expect(text).to.be("Affinito2")
      browser.byCsss("h1 img").then (els) ->
        expect(els.length).to.be(0)
        www_schema.Group.findOne {name: "Affinito2"}, (err, doc) ->
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          expect(doc.name).to.be("Affinito2")
          expect(doc.slug).to.be("affinito2")
          expect(doc.logo.full).to.be(null)
          expect(doc.logo.thumb).to.be(null)
          expect(doc.members.length).to.be(1)
          expect(doc.invited_members.length).to.be(2)
          expect(!!doc.disabled).to.be(false)
          done()

  it "adds and removes members from invitations list", (done) ->
    www_schema.Group.findOne(
      {slug: "three-members"}
    ).populate('members.user invited_members.user').exec (err, group) ->
      selfEmail = "one@mockmyid.com"
      common.stubAuthenticate browser, selfEmail, (err) ->
        
        browser.get("http://localhost:#{config.port}/groups/edit/#{group.slug}")

        #
        # Helpers
        #

        # Add an invitee.
        add = (email) ->
          browser.byCss("#add_email").clear()
          browser.byCss("#add_email").sendKeys(email)
          browser.byCss(".add-new-invitee").click()

        # Remove or undo remove.
        remove = (email) ->
          browser.byCss("tr:not(.removed) .remove[data-email='#{email}']").click()

        undo = (email) ->
          browser.byCss("tr.removed .remove[data-email='#{email}']").click()

        # Ensure that the email is present in the table -- either marked for
        # removal or not.
        confirmExists = (email, exists) ->
          browser.wait ->
            browser.byCsss(".remove[data-email='#{email}']").then (els) ->
              if exists
                return els.length == 1
              else
                return els.length == 0

        # Check the marked-for-removal state of an email which exists in the table.
        confirmRemoved = (email, removed) ->
          if removed
            prefix = "tr.removed "
          else
            prefix = "tr:not(.removed) "
          browser.byCsss("#{prefix} .remove[data-email='#{email}']").then (els) ->
            browser.wait ->
              return els.length == 1

        # Count the number of not-marked-for-removal members in the table.
        memberCounts = (types) ->
          for type, count of types
            browser.wait ->
              browser.byCsss("tr.member.#{type}:not(.removed)").then (els) ->
                return els.length == count

        infoMessage = (text) ->
          browser.waitForSelector("li.info")
          browser.byCss("li.info").getText().then (text) ->
            expect(text).to.be(text)
          browser.executeScript("$('li.info').remove();")

        #
        # Tests
        #
        
        # Add an invitee, and it appears
        add("test@example.com")
        confirmExists("test@example.com", true)
        memberCounts({current: 3, invited: 1, newinvitee: 1})
        # Ensure the text matches as expected.
        browser.waitForSelector(".member.newinvitee td")
        browser.byCss(".member.newinvitee td").getText().then (text) ->
          expect(text).to.eql("test@example.com")
        
        # Remove the new invitee, and it disappears.
        remove("test@example.com")
        confirmExists("test@example.com", false)
        memberCounts({current: 3, invited: 1, newinvitee: 0})

        # Re-add the invitee and they re-appear.
        add("test@example.com")
        confirmExists("test@example.com", true)
        memberCounts({current: 3, invited: 1, newinvitee: 1})

        # Adding an email matching an existing new invitation fails.
        add("test@example.com")
        confirmExists("test@example.com", true)
        memberCounts({current: 3, invited: 1, newinvitee: 1})
        
        # Adding an email matching an existing old invitation fails.
        email = group.invited_members[0].user.email
        confirmExists(email, true)
        add(email)
        infoMessage("That user has already been invited.")
        confirmExists(email, true)
        memberCounts({current: 3, invited: 1, newinvitee: 1})
        
        # Adding an email matching a member fails.
        email = group.members[0].user.email
        confirmExists(email, true)
        add(email)
        infoMessage("That user is already a member.")
        browser.executeScript("$('li.info').remove();")

        # Removing an existing member crosses them out, and gives an undo link.
        remove(group.members[1].user.email)
        memberCounts({current: 2, invited: 1, newinvitee: 1})
        undo(group.members[1].user.email)
        memberCounts({current: 3, invited: 1, newinvitee: 1})

        # Everyone but our self, used for the next couple tests.
        notSelfMembers = (m for m in group.members when m.user.email != selfEmail)

        # Can't remove last member wich equals self.  This checks the case
        # where we try to remove ourselves last.
        for membership in notSelfMembers
          remove(membership.user.email)
          confirmRemoved(membership.user.email, true)
        remove(selfEmail)
        infoMessage("There must be other group members before you remove yourself.")
        confirmRemoved(selfEmail, false)
        memberCounts({current: 1, invited: 1, newinvitee: 1})

        # Can't remove last member who isn't ourself.
        undo(notSelfMembers[0].user.email)
        remove(selfEmail)
        confirmRemoved(selfEmail, true)
        memberCounts({current: 1, invited: 1, newinvitee: 1})
        remove(notSelfMembers[0].user.email)
        confirmRemoved(notSelfMembers[0].user.email, false)
        memberCounts({current: 1, invited: 1, newinvitee: 1})
        infoMessage("There must be at least one group member.")
        # reset
        undo(selfEmail)
        remove(notSelfMembers[0].user.email)
        for membership in notSelfMembers
          undo(membership.user.email)
        memberCounts({current: 3, invited: 1, newinvitee: 1})
        
        # Removing invited works too, b-t-dubs.
        email = group.invited_members[0].user.email
        remove(email)
        confirmRemoved(email, true)
        memberCounts({current: 3, invited: 0, newinvitee: 1})
        undo(email)
        memberCounts({current: 3, invited: 1, newinvitee: 1})

        # hack to get a promise.
        browser.executeScript("return true;").then -> done()
        ###
        ###
