use stallion = "stallion"

class iso RouteGroup
  """
  A group of routes sharing a common path prefix and optional interceptors.

  Route groups let you factor out repeated prefixes and interceptors instead of
  attaching them to every route individually. Groups can be nested — inner
  groups inherit the outer group's prefix and interceptors, with the outer
  interceptors running first.

  ```pony
  let auth_interceptors: Array[hobby.RequestInterceptor val] val =
    recover val [as hobby.RequestInterceptor val: AuthInterceptor] end
  let api = hobby.RouteGroup("/api" where interceptors = auth_interceptors)
  api.>get("/users", users_factory)
  api.>get("/users/:id", user_factory)
  app.>group(consume api)
  ```

  Route methods are `fun ref` — automatic receiver recovery allows calling
  them on an `iso` receiver since all arguments are `val`. Use `.>` to chain
  route calls. Pass the group to `Application.group()` or an outer
  `RouteGroup.group()` when done — this consumes the group and flattens its
  routes.
  """
  let _prefix: String
  let _interceptors: (Array[RequestInterceptor val] val | None)
  let _response_interceptors: (Array[ResponseInterceptor val] val | None)
  embed _routes: Array[_RouteDefinition]

  new iso create(prefix: String,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Create a route group with a path prefix and optional interceptors.

    The prefix is prepended to every route path in the group. Request
    interceptors, if provided, run before each route's own interceptors.
    Response interceptors, if provided, run before each route's own response
    interceptors.
    """
    _prefix = prefix
    _interceptors = interceptors
    _response_interceptors = response_interceptors
    _routes = Array[_RouteDefinition]

  fun ref get(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a GET route."""
    _routes.push(
      _RouteDefinition(stallion.GET, path, factory, response_interceptors,
        interceptors))

  fun ref post(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a POST route."""
    _routes.push(
      _RouteDefinition(stallion.POST, path, factory, response_interceptors,
        interceptors))

  fun ref put(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a PUT route."""
    _routes.push(
      _RouteDefinition(stallion.PUT, path, factory, response_interceptors,
        interceptors))

  fun ref delete(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a DELETE route."""
    _routes.push(
      _RouteDefinition(stallion.DELETE, path, factory, response_interceptors,
        interceptors))

  fun ref patch(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a PATCH route."""
    _routes.push(
      _RouteDefinition(stallion.PATCH, path, factory, response_interceptors,
        interceptors))

  fun ref head(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a HEAD route."""
    _routes.push(
      _RouteDefinition(stallion.HEAD, path, factory, response_interceptors,
        interceptors))

  fun ref options(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register an OPTIONS route."""
    _routes.push(
      _RouteDefinition(stallion.OPTIONS, path, factory, response_interceptors,
        interceptors))

  fun ref route(method: stallion.Method, path: String,
    factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a route with an arbitrary HTTP method."""
    _routes.push(
      _RouteDefinition(method, path, factory, response_interceptors,
        interceptors))

  fun ref group(inner: RouteGroup iso) =>
    """
    Consume a nested route group, flattening its routes into this group.

    The inner group's prefix is appended to this group's prefix, and the inner
    group's interceptors are appended after this group's interceptors. The inner
    group is consumed — no further registration on it is possible.
    """
    let inner_ref: RouteGroup ref = consume inner
    inner_ref._flatten_into(_routes)

  fun box _flatten_into(target: Array[_RouteDefinition] ref) =>
    for r in _routes.values() do
      let joined_path = _JoinPath(_prefix, r.path)
      let combined_interceptors =
        _ConcatInterceptors(_interceptors, r.interceptors)
      let combined_response_interceptors =
        _ConcatResponseInterceptors(_response_interceptors,
          r.response_interceptors)
      target.push(_RouteDefinition(r.method, joined_path, r.factory,
        combined_response_interceptors, combined_interceptors))
    end
