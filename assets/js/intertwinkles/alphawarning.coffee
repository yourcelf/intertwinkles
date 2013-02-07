modal_template = """
  <div class='modal fade'>
    <div class='modal-header'>
      <button class='close' type='button' data-dismiss='modal' aria-hidden='true'>&times;</button>
      <h3>Super Alpha!</h3>
    <div class='modal-body'>
      <p>Thanks for stopping by -- this is a testing preview of InterTwinkles.  Data may be periodically deleted, so feel free to poke around.</p>
      <p>Want to find out more?</p>
      <ul>
        <li><a href='https://twitter.com/intertwinkles'>Follow us on twitter</a></li>
        <li>Email: <a href='mailto:cfd@media.mit.edu'>cfd@media.mit.edu</a></li>
        <li><a href='http://project.intertwinkles.org'>Project site</a></li>
      </ul>
      <p>In the next 8 months I'm going to be running a series of free workshops exploring online consensus decision making process.  If your group might be interested, <a href='mailto:cfd@media.mit.edu'>contact me!</a>
      </p>
    </div>
    <div class='modal-footer'>
      <a class='btn btn-primary' data-dismiss='modal'>Got it!</a>
    </div>
  </div>
"""
unless $.cookie("intertwinklesalpha")
  modal = $(modal_template)
  $("body").append(modal)
  modal.modal('show')
  opts = {expires: 1, path: '/'}
  if intertwinkles.ALPHA_COOKIE_DOMAIN
    opts.domain = intertwinkles.ALPHA_COOKIE_DOMAIN
  $.cookie("intertwinklesalpha", "yup", opts)
