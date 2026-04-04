// in your code this `use` statement would be:
// use hobby = "hobby"
use "files"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  """

  Static file serving example.

  Starts an HTTP server on 0.0.0.0:8080 that serves files from a directory
  given as a command-line argument, under the `/static/` URL prefix.
  Directory requests automatically serve `index.html` if present (e.g.,
  `/static/docs/` serves `public/docs/index.html`).

  Usage:
    serve-files /path/to/public

  Try it:
    ./build/release/serve-files examples/serve-files/public
    curl http://localhost:8080/
    curl http://localhost:8080/static/index.html
    curl http://localhost:8080/static/style.css
    curl http://localhost:8080/static/docs/
  """

  let _env: Env

  new create(env: Env) =>
    _env = env
    try
      let dir = env.args(1)?
      let auth = lori.TCPListenAuth(env.root)
      let root = FilePath(FileAuth(env.root), dir)

      let app = hobby.Application
        .> get(
          "/",
          {(ctx) =>
            hobby.RequestHandler(consume ctx)
              .respond(
                stallion.StatusOK,
                "Visit /static/index.html"
                  + " to see a served file.")
          } val)
        .> get("/static/*filepath", hobby.ServeFiles(root))

      match \exhaustive\ app.build()
      | let built: hobby.BuiltApplication =>
        hobby.Server(
          auth, built, this
          where host = "0.0.0.0", port = "8080")
      | let err: hobby.ConfigError =>
        env.err.print(err.message)
      end
    else
      env.err.print("Usage: serve-files <directory>")
      env.exitcode(1)
    end

  be listening(
    server: hobby.Server,
    host: String,
    service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)

  be listen_failed(
    server: hobby.Server,
    reason: String)
  =>
    _env.err.print(reason)
