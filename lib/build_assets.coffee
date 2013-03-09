stylus    = require 'stylus'
Snockets  = require('snockets')
less      = require 'less'
nib       = require 'nib'
fs        = require 'fs'
path      = require 'path'
async     = require 'async'
logger    = require('log4js').getLogger('assets')

# plugin path
asset_folders = [
  __dirname + "/../assets",
  __dirname + "/../plugins/dotstorm/assets",
  __dirname + "/../plugins/resolve/assets",
  __dirname + "/../plugins/firestarter/assets",
  __dirname + "/../plugins/twinklepad/assets",
]

compiled_files = [
  "/js/intertwinkles/index.coffee"
  "/js/home/home.coffee"
  "/js/home/landing.coffee"
  "/js/home/membership.coffee"
  "/firestarter/js/frontend.coffee"
  "/twinklepad/js/frontend.coffee"
  "/resolve/js/frontend.coffee"
  "/dotstorm/js/frontend.coffee"
  "/css/intertwinkles.styl"
  "/css/landing.styl"
  "/css/home.styl"
  "/firestarter/css/style.styl"
  "/twinklepad/css/style.styl"
  "/resolve/css/style.styl"
  "/dotstorm/css/style.styl"
  "/css/bootstrap.less"
]

write = (filepath, contents) ->
  mkdirs(path.dirname(filepath))
  fs.writeFileSync(filepath, contents, 'utf-8')

snockets = new Snockets()
compile_coffee = (src, dest) ->
  write(dest, snockets.getConcatenation(src, {async: false, minify: true}))

compile_stylus = (src, dest) ->
  code = fs.readFileSync(src, 'utf-8')
  stylus(code)
    .set('filename', src)
    .set('compress', true)
    .use(nib())
    .import('nib')
    .render((err, css) ->
      throw(err) if err?
      write(dest, css, 'utf-8')
    )

compile_less = (src, dest) ->
  parser = new less.Parser(paths: [path.dirname(src)])
  code = fs.readFileSync(src, 'utf-8')
  parser.parse(code, (err, tree) ->
    if err?
      logger.error(err)
      throw(err) if err?
    write(dest, tree.toCSS({compress: true}), 'utf-8')
  )

mkdirs = (dir) ->
  if fs.existsSync(dir)
    return
  else
    parent = path.dirname(dir)
    mkdirs(parent)
    fs.mkdirSync(dir)

copy_files = (dir, parent, destRoot) ->
  for name in fs.readdirSync(dir)
    full_name = path.normalize(dir + "/" + name)
    stats = fs.statSync(full_name)
    if stats.isDirectory()
      copy_files(full_name, parent, destRoot)
    else
      rel_name = path.relative(parent, full_name)
      dest = destRoot + "/" + rel_name
      mkdirs(path.dirname(dest))
      fs.writeFileSync(dest, fs.readFileSync(full_name))

compile_one = (filename) ->
  ext = path.extname(filename)
  switch ext
    when ".coffee"
      new_ext = ".js"
      compile = compile_coffee
    when ".styl"
      new_ext = ".css"
      compile = compile_stylus
    when ".less"
      new_ext = ".css"
      compile = compile_less
  dest = filename.substring(0, filename.length - ext.length) + new_ext
  logger.info("Compile", filename, "=>", dest)
  compile(filename, dest)

compile_all = (destRoot) ->
  destRoot = path.normalize(destRoot)
  # Copy *all* the assets to the destination.
  for dir in asset_folders
    copy_files(dir, dir, destRoot)

  # Compile those that need compilation.
  for file in compiled_files
    compile_one(destRoot + file)


watchTimeout = null
_watch = (dir, destRoot) ->
  # Ugly, ugly, ugly. Re-build everything when anything changes.
  for name in fs.readdirSync(dir)
    filename = path.normalize(dir + "/" + name)
    if filename.substring(0, 1) == "."
      continue
    if fs.statSync(filename).isDirectory()
      _watch(filename, destRoot)
    else
      fs.watch filename, (event, filename) ->
        clearTimeout(watchTimeout) if watchTimeout?
        watchTimeout = setTimeout((-> compile_all destRoot), 100)

watch = (destRoot) ->
  for dir in asset_folders
    _watch(dir, destRoot)

module.exports = {compile_all, watch}
