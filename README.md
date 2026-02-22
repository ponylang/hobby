# hobby

A simple HTTP web framework for [Pony](https://www.ponylang.io/), inspired by [Jennet](https://github.com/Theodus/jennet) and powered by [Stallion](https://github.com/ponylang/stallion).

## Status

hobby is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/hobby.git --version 0.0.0`
* `corral fetch` to fetch your dependencies
* `use "hobby"` to include this package
* `corral run -- ponyc` to compile your application

## Usage

See the [examples](examples/) directory for working programs that demonstrate hobby's API, including a basic hello-world server and middleware usage.

## API Documentation

[https://ponylang.github.io/hobby](https://ponylang.github.io/hobby)
