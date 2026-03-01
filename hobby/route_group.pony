use stallion = "stallion"

class iso RouteGroup
  """
  A group of routes sharing a common path prefix and optional
  middleware.

  Route groups let you factor out repeated prefixes and middleware
  instead of attaching them to every route individually. Groups can
  be nested -- inner groups inherit the outer group's prefix and
  middleware, with the outer middleware running first.

  ```pony
  let api = hobby.RouteGroup(
    "/api" where middleware = auth_mw)
  api.>get("/users", UsersHandler)
  api.>get("/users/:id", UserHandler)
  app.>group(consume api)
  ```

  Route methods are `fun ref` -- automatic receiver recovery allows
  calling them on an `iso` receiver since all arguments are `val`.
  Use `.>` to chain route calls. Pass the group to
  `Application.group()` or an outer `RouteGroup.group()` when
  done -- this consumes the group and flattens its routes.
  """
  let _prefix: String
  let _middleware: (Array[Middleware val] val | None)
  embed _routes: Array[_RouteDefinition]

  new iso create(
    prefix: String,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Create a route group with a path prefix and optional middleware.

    The prefix is prepended to every route path in the group.
    Middleware, if provided, runs before each route's own middleware.
    """
    _prefix = prefix
    _middleware = middleware
    _routes = Array[_RouteDefinition]

  fun ref get(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a GET route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.GET, path, handler, middleware))

  fun ref post(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a POST route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.POST, path, handler, middleware))

  fun ref put(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a PUT route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PUT, path, handler, middleware))

  fun ref delete(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a DELETE route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.DELETE, path, handler, middleware))

  fun ref patch(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a PATCH route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PATCH, path, handler, middleware))

  fun ref head(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a HEAD route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.HEAD, path, handler, middleware))

  fun ref options(
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register an OPTIONS route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.OPTIONS, path, handler, middleware))

  fun ref route(
    method: stallion.Method,
    path: String,
    handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """
    Register a route with an arbitrary HTTP method.
    """
    _routes.push(
      _RouteDefinition(
        method, path, handler, middleware))

  fun ref group(inner: RouteGroup iso) =>
    """
    Consume a nested route group, flattening its routes into this
    group.

    The inner group's prefix is appended to this group's prefix,
    and the inner group's middleware is appended after this group's
    middleware. The inner group is consumed -- no further
    registration on it is possible.
    """
    let inner_ref: RouteGroup ref = consume inner
    inner_ref._flatten_into(_routes)

  fun box _flatten_into(
    target: Array[_RouteDefinition] ref)
  =>
    for r in _routes.values() do
      let joined_path =
        _JoinPath(_prefix, r.path)
      let combined_mw =
        _ConcatMiddleware(_middleware, r.middleware)
      target.push(
        _RouteDefinition(
          r.method,
          joined_path,
          r.handler,
          combined_mw))
    end
