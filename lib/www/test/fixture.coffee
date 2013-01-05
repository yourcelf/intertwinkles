module.exports = {
  users: [
    {
      name: "One"
      joined: new Date()
      email: "one@mockmyid.com"
      mobile: { number: null, carrier: null }
    },
    {
      name: "Two"
      joined: new Date()
      email: "two@mockmyid.com"
      mobile: { number: "5555555555", carrier: "T-Mobile" }
    },
    {
      name: "Three"
      joined: new Date()
      email: "three@mockmyid.com"
      mobile: { number: "5556667777", carrier: "Alltel" }
    },
    {
      name: "Four"
      joined: new Date()
      email: "four@mockmyid.com"
      mobile: { number: "5556667777", carrier: "Alltel" }
    },
    {
      name: "Change request"
      joined: new Date()
      email: "old_address@mockmyid.com"
      email_change_request: "new_address@mockmyid.com"
      mobile: { number: "5556666666", carrier: "US Cellular" }
    },
  ]
  groups: [
    {
      name: "Two Members"
      slug: "two-members"
      disabled: false
      logo: null
      created: new Date(2012,1,1)
      members: [{
        user: "One" # Will be swapped with UserID from above user when loaded
        voting: true
        joined: new Date(2012,1,1)
      }, {
        user: "Two"
        invited_by: "One"
        invited_on: new Date(2012,2,2)
        joined: new Date(2012,2,3)
        voting: true
      }],
      past_members: [{
        user:  "Three"
        invited_by: "One"
        invited_on: new Date(2012,1,2)
        joined: new Date(2012,1,3)
        left: new Date(2012,5,5)
      }]
    },
    {
      name: "Not one members"
      slug: "not-one-members"
      created: new Date(2012,1,1)
      members: [{
        user: "Two"
        voting: true
        joined: new Date(2012,1,1)
      }]
    },
    {
      name: "Three members"
      slug: "three-members"
      disabled: false
      logo: null
      created: new Date()
      members: [{
        user: "One"
        voting: false
        role: "Facilitator"
        joined: new Date()
      },
      {
        user: "Two"
        voting: true
        invited_by: "One"
        invited_on: new Date()
        joined: new Date()
        role: "Secretary"
      },
      {
        user: "Three"
        voting: true
        invited_by: "One"
        invited_on: new Date()
        joined: new Date()
        role: "Treasurer"
      }],
      invited_members: [{
        user: "Four"
        invitation_sent: null
        voting: true
        invited_by: "One"
        invited_on: new Date()
        joined: new Date()
        role: "President"
      }],
    },
    {
      name: "Change requester"
      slug: "change-requester"
      members: [{ user: "Change request", joined: new Date(), voting: true}]
    },
  ]
}
