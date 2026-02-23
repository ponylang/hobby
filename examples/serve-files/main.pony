// in your code this `use` statement would be:
// use hobby = "hobby"
use "files"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Static file serving example.

  Starts an HTTP server on 0.0.0.0:8080 that serves files from a directory
  given as a command-line argument, under the `/static/` URL prefix.

  Usage:
    serve-files /path/to/public

  Try it:
    ./build/release/serve-files examples/serve-files/public
    curl http://localhost:8080/
    curl http://localhost:8080/static/index.html
    curl http://localhost:8080/static/style.css
  """
  new create(env: Env) =>
    try
      let dir = env.args(1)?
      let auth = lori.TCPListenAuth(env.root)
      let root = FilePath(FileAuth(env.root), dir)

      hobby.Application
        .>get("/", IndexHandler)
        .>get("/static/*filepath", hobby.ServeFiles(root))
        .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
    else
      env.err.print("Usage: serve-files <directory>")
      env.exitcode(1)
    end

primitive IndexHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK,
      "Visit /static/index.html to see a served file.")
