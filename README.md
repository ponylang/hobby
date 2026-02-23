# hobby

A simple HTTP web framework for Pony, inspired by [Jennet](https://github.com/Theodus/jennet) and powered by [Stallion](https://github.com/ponylang/stallion).

## Status

hobby is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/hobby.git --version 0.2.0`
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
      .>get("/", HelloHandler)
      .>get("/greet/:name", GreetHandler)
      .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)

primitive HelloHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello!")

class val GreetHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) ? =>
    ctx.respond(stallion.StatusOK, "Hello, " + ctx.param("name")? + "!")
```

See the [examples](examples/) directory for more, including middleware usage. For a detailed walkthrough, read the [Writing Middleware](docs/middleware-guide.md) guide.

## API Documentation

[https://ponylang.github.io/hobby](https://ponylang.github.io/hobby)
