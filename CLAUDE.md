# hobby

A simple HTTP web framework for Pony, inspired by [Jennet](https://github.com/Theodus/jennet) and powered by [Stallion](https://github.com/ponylang/stallion).

Design: https://github.com/ponylang/hobby/discussions/2

## Building and Testing

```bash
make                    # build tests + examples (release)
make test               # same as above
make config=debug       # debug build
make build-examples     # examples only
make clean              # clean build artifacts + corral cache
```

`make test` runs unit tests, integration tests, and builds examples. `make unit-tests` and `make integration-tests` can be run individually.

## Dependencies

- **Stallion** (0.1.0): HTTP/1.x server built on lori. Provides `HTTPServerActor`, `HTTPServer`, `Responder`, `ResponseBuilder`, `Request`, `ServerConfig`, `Status`, `Method`, `Headers`.
- **lori** (transitive via Stallion): TCP layer. Provides `TCPListenerActor`, `TCPListener`, `TCPConnectionActor`, `TCPConnection`, auth types.
- **uri** (transitive via Stallion): URI parsing. Used to read `request.uri.path`.

## Architecture

### Public API

Users interact with four types:

- **`Application`** (`class iso`): Route registration via `.>` chaining (`get`, `post`, etc.). `serve()` consumes the Application, freezes routes into an immutable router, and starts listening.
- **`Handler`** (`interface val`): Request handler. Receives `Context ref`, calls `ctx.respond()` to send a response. Partial (`?`) — errors without responding produce 500.
- **`Middleware`** (`interface val`): Two-phase processor. `before` (partial) runs before the handler; `after` (not partial) runs after, in reverse order.
- **`Context`** (`class ref`): Request context with route params, body, data map, and respond methods.

### Internal layers

- **`_Listener`** (`actor`): Implements `lori.TCPListenerActor`. Accepts TCP connections and spawns `_Connection` actors.
- **`_Connection`** (`actor`): Implements `stallion.HTTPServerActor`. Accumulates body chunks, runs route lookup, executes middleware chain + handler via `_ChainRunner`. Sends 404 for unmatched routes.
- **`_Router`** (`class val`): Immutable radix tree router. One tree per HTTP method. Built from `_RouterBuilder` (mutable `_BuildNode ref` trees frozen into `_TreeNode val` trees).
- **`_ChainRunner`** (`primitive`): Executes middleware `before` phases, then handler, then middleware `after` phases in reverse. Tracks invocation count so `after` runs for every middleware whose `before` was called.

### Key design decisions

- **Context is `ref`, not `iso`**: Avoids the iso consumption problem — if middleware errors after consuming an iso Context, the Context is lost. With `ref`, it survives errors and `after` phases always have access.
- **Route methods are `fun ref`**: Auto receiver recovery handles calling them on the `iso` Application since all arguments are `val`. `serve()` is `fun iso` and uses `consume this`.
- **Build/lookup separation**: Mutable `_BuildNode ref` trees for construction, frozen into immutable `_TreeNode val` trees for lookup. Params built bottom-up as `val` arrays to avoid ref-to-val boundary issues in recover blocks.
- **Static priority**: Static children checked before param child during lookup.
- **Trailing slash normalization**: `/users/` and `/users` match the same route.

## File Layout

```
hobby/
  hobby.pony              - Package docstring
  context.pony            - Context class (public)
  handler.pony            - Handler interface (public)
  middleware.pony          - Middleware interface (public)
  application.pony        - Application class (public)
  _connection.pony        - Connection actor (internal)
  _listener.pony          - Listener actor (internal)
  _router.pony            - Router + radix tree (internal)
  _route_match.pony       - Route match result type (internal)
  _route_definition.pony  - Route definition for building (internal)
  _chain_runner.pony      - Middleware chain execution (internal)
  _mort.pony              - _Unreachable primitive (internal)
  _test.pony              - Test runner
  _test_router.pony       - Router property-based + example tests
  _test_integration.pony  - HTTP round-trip integration tests
```

## Conventions

- Private types (`_` prefix) are package-private, accessible within `hobby/` but not externally.
- All public API elements have docstrings.
- `_Unreachable()` is used in `else` branches of `try` blocks where the error path is impossible due to prior bounds checks.
- Integration tests use `label(): String => "integration"` for selective execution.
- WSL2 compatibility: integration tests use `127.0.0.2` on Linux to avoid the Hyper-V mirrored networking bug (see ponylang/lori#153).
