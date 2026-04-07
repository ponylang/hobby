# hobby

An HTTP server framework for Pony, powered by [Stallion](https://github.com/ponylang/stallion). Features include route parameter extraction, middleware, route groups, static file serving, streaming responses, and actor-per-request async handlers.

## Status

hobby is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/hobby.git --version 0.6.1`
* `corral fetch` to fetch your dependencies
* `use "hobby"` to include this package
* `corral run -- ponyc` to compile your application

Note: The ssl transitive dependency requires a C SSL library to be installed. Please see the ssl installation instructions for more information.

## Usage

```pony
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let app = hobby.Application
      .>get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "Hello!")
      } val)
      .>get("/greet/:name", {(ctx) =>
        let handler = hobby.RequestHandler(consume ctx)
        try
          let name = handler.param("name")?
          handler.respond(stallion.StatusOK, "Hello, " + name + "!")
        else
          handler.respond(stallion.StatusBadRequest, "Bad Request")
        end
      } val)

    match app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(auth, built, this
        where host = "localhost", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(server: hobby.Server, host: String, service: String) =>
    _env.out.print("Listening on " + host + ":" + service)
```

See the [examples](examples/) directory for more, including interceptor usage. For a detailed walkthrough, read the [Writing Request Interceptors](docs/interceptor-guide.md) guide.

## API Documentation

[https://ponylang.github.io/hobby](https://ponylang.github.io/hobby)
