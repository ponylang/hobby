// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  """
  Hello world example.

  Starts an HTTP server on 0.0.0.0:8080 with two routes:
  - GET /         -> "Hello from Hobby!"
  - GET /greet/:name -> "Hello, <name>!"

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/greet/World
  """
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let app = hobby.Application
      .> get(
        "/",
        {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello from Hobby!")
        } val)
      .> get(
        "/greet/:name",
        {(ctx) =>
          let handler = hobby.RequestHandler(consume ctx)
          try
            let name = handler.param("name")?
            handler.respond(
              stallion.StatusOK, "Hello, " + name + "!")
          else
            handler.respond(
              stallion.StatusBadRequest, "Bad Request")
          end
        } val)

    match \exhaustive\ app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(
        auth, built, this
        where host = "0.0.0.0", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
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
