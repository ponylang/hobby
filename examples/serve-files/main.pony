// in your code this `use` statement would be:
// use hobby = "hobby"
use "files"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Static file serving example.

  Starts an HTTP server on 0.0.0.0:8080 that serves files from a `public/`
  directory under the `/static/` URL prefix.

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/static/index.html
    curl http://localhost:8080/static/style.css
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let root = FilePath(FileAuth(env.root), "./public")

    hobby.Application
      .>get("/", IndexHandler)
      .>get("/static/*filepath", hobby.ServeFiles(root))
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

primitive IndexHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK,
      "Visit /static/index.html to see a served file.")
