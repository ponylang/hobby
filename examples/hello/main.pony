// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Hello world example.

  Starts an HTTP server on 0.0.0.0:8080 with two routes:
  - GET /         -> "Hello from Hobby!"
  - GET /greet/:name -> "Hello, <name>!"

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/greet/World
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    hobby.Application
      .>get("/", HelloHandler)
      .>get("/greet/:name", GreetHandler)
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

primitive HelloHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello from Hobby!")

class val GreetHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) ? =>
    let name = ctx.param("name")?
    ctx.respond(stallion.StatusOK, "Hello, " + name + "!")
