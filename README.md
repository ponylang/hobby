# hobby

A simple HTTP web framework for Pony, inspired by [Jennet](https://github.com/Theodus/jennet) and powered by [Stallion](https://github.com/ponylang/stallion).

## Status

hobby is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/hobby.git --version 0.4.0`
* `corral fetch` to fetch your dependencies
* `use "hobby"` to include this package
* `corral run -- ponyc` to compile your application

## Usage

```pony
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    hobby.Application
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
      .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
```

See the [examples](examples/) directory for more, including middleware usage. For a detailed walkthrough, read the [Writing Middleware](docs/middleware-guide.md) guide.

## API Documentation

[https://ponylang.github.io/hobby](https://ponylang.github.io/hobby)
