# hobby

An HTTP server framework for Pony, built on [Stallion](https://github.com/ponylang/stallion).

Design discussions: [overview](https://github.com/ponylang/hobby/discussions/2), [static file serving](https://github.com/ponylang/hobby/discussions/18), [actor-per-request](https://github.com/ponylang/hobby/discussions/41), [shared path tree](https://github.com/ponylang/hobby/discussions/58), [separate build/serve](https://github.com/ponylang/hobby/discussions/79).

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Prose model

If you are running on an Anthropic model, use `claude-opus-4-6` for writing comments, documentation, and other prose. Prose quality from Anthropic models dropped starting with Opus 4.7 and has gotten worse with each subsequent release.

## Linting

Run `make lint` before considering any work done. Fix all issues it reports. `make lint` runs pony-lint, which checks for style and correctness problems in Pony source files. A clean lint run is part of "done" — don't open a PR or report completion with lint issues outstanding.

## Building and testing

```bash
make ssl=3.0.x                      # run unit + integration tests, build examples
make test ssl=3.0.x                 # same (test is the default target)
make test-one t=TestName ssl=3.0.x  # run a single test by name
make unit-tests ssl=3.0.x           # unit tests only
make integration-tests ssl=3.0.x    # integration tests only
make examples ssl=3.0.x             # examples only
make config=debug ssl=3.0.x         # debug build
make clean                          # clean build artifacts + corral cache
make lint                           # run pony-lint
```

`ssl=` is required (Stallion pulls in `ssl`): `3.0.x`, `1.1.x`, or `libressl` (CI uses libressl). Run `make lint` before pushing.

## Architecture

Routing and serving are separate phases. `Application` (a `ref` builder) registers routes and interceptors; `Application.build()` validates them and freezes a `BuiltApplication val` — a token that proves the routes compiled, shareable across actors and reusable by several `Server`s. A `Server` (HTTP) or `Server.ssl()` (HTTPS, which requires an `SSLContext val`) takes that token and listens.

Each request runs in its own handler: the route's `HandlerFactory` may spawn an actor that does async work — a database query, an outbound call — and responds when it is ready, so the connection never blocks. Requests are matched by `_Router`, a single immutable segment trie shared across all HTTP methods, with lookup priority static > param > wildcard.

The design rationale for each of these is in the discussions linked at the top.

## Conventions

- Every public API element has a docstring.
- `_Unreachable()` goes in the `else` of a `try` whose error path is impossible due to prior checks.
- `\nodoc\` on every test class, primitive, and actor.
- Integration tests declare `label(): String => "integration"` for selective runs.
- On Linux, integration tests connect to `127.0.0.2` rather than the usual loopback, to dodge the WSL2 Hyper-V mirrored-networking hang (see ponylang/lori#153).
