use stallion = "stallion"

class ref Application
  """
  Mutable route builder for the Hobby web framework.

  Register routes via `.>` method chaining (`get`, `post`, etc.), then
  call `build()` to validate and freeze the routes into a
  `BuiltApplication`. Pass the result to `Server` to start listening.

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
        .> get("/", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello!")
        } val)

      match app.build()
      | let built: hobby.BuiltApplication =>
        hobby.Server(auth, built, this
          where host = "localhost", port = "8080")
      | let err: hobby.ConfigError =>
        env.err.print(err.message)
      end

    be listening(server: hobby.Server,
      host: String, service: String)
    =>
      _env.out.print(
        "Listening on " + host + ":" + service)
  ```

  `Application` is `ref` — it is a builder that produces snapshots. You
  can build routes, call `build()` to freeze a snapshot, add more
  routes, and build again. Each `BuiltApplication` is independent.
  """
  embed _routes: Array[_RouteDefinition]
  embed _app_interceptors: Array[RequestInterceptor val]
  embed _app_response_interceptors: Array[ResponseInterceptor val]
  embed _group_infos: Array[_GroupInfo]

  new create() =>
    _routes = Array[_RouteDefinition]
    _app_interceptors = Array[RequestInterceptor val]
    _app_response_interceptors = Array[ResponseInterceptor val]
    _group_infos = Array[_GroupInfo]

  fun ref get(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a GET route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.GET,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref post(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a POST route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.POST,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref put(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a PUT route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PUT,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref delete(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a DELETE route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.DELETE,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref patch(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a PATCH route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PATCH,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref head(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a HEAD route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.HEAD,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref options(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register an OPTIONS route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.OPTIONS,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref route(
    method: stallion.Method,
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a route with an arbitrary HTTP method.
    """
    _routes.push(
      _RouteDefinition(
        method,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref add_request_interceptor(interceptor: RequestInterceptor val) =>
    """
    Add an application-level request interceptor.

    Request interceptors run before the handler on every request. Application
    interceptors run before group interceptors, which run before per-route
    interceptors. The first interceptor that returns `InterceptRespond` rejects
    the request — the handler is never created.

    App-level interceptors also run on 404 responses where no route matched.
    """
    _app_interceptors.push(interceptor)

  fun ref add_response_interceptor(interceptor: ResponseInterceptor val) =>
    """
    Add an application-level response interceptor.

    Response interceptors run after the handler responds, before the response
    goes to the wire. Application interceptors run before group interceptors,
    which run before per-route interceptors. All interceptors run — there is
    no short-circuiting.

    App-level response interceptors also run on 404 responses where no route
    matched.
    """
    _app_response_interceptors.push(interceptor)

  fun ref group(g: RouteGroup iso) =>
    """
    Consume a route group, flattening its routes into this application.

    The group's prefix is applied to each of its routes. Group-level
    interceptors are preserved separately for tree building — they are
    registered on path nodes, not concatenated onto routes. The group is
    consumed — no further registration on it is possible.
    """
    (consume g)
      .> _collect_group_infos(_group_infos)
      .> _flatten_routes_into(_routes)

  fun ref build(): BuildResult =>
    """
    Validate routes and freeze them into a `BuiltApplication`.

    Returns `BuiltApplication` on success or `ConfigError` if a
    configuration error was detected (overlapping group prefixes,
    invalid group prefix, conflicting param or wildcard names, empty
    param name, empty wildcard name).

    The Application is not consumed — you can add more routes and call
    `build()` again. Each `BuiltApplication` is an independent
    snapshot.
    """
    // Validate group configuration before building
    match _ValidateGroups(_group_infos)
    | let err: ConfigError => return err
    end

    // Build app-level request interceptors as a val array (or None
    // if empty)
    let app_interceptors:
      (Array[RequestInterceptor val] val | None)
    =
      if _app_interceptors.size() > 0 then
        let gs_iso: Array[RequestInterceptor val] iso =
          recover iso Array[RequestInterceptor val] end
        for g in _app_interceptors.values() do
          gs_iso.push(g)
        end
        consume gs_iso
      else
        None
      end

    // Build app-level response interceptors as a val array (or None
    // if empty)
    let app_response_interceptors:
      (Array[ResponseInterceptor val] val | None)
    =
      if _app_response_interceptors.size() > 0 then
        let ri_iso: Array[ResponseInterceptor val] iso =
          recover iso Array[ResponseInterceptor val] end
        for ri in _app_response_interceptors.values() do
          ri_iso.push(ri)
        end
        consume ri_iso
      else
        None
      end

    let builder = _RouterBuilder

    // Register app-level interceptors on the root node
    builder.add_interceptors(
      "", app_interceptors, app_response_interceptors)

    // Register group-level interceptors on their prefix nodes
    for gi in _group_infos.values() do
      builder.add_interceptors(
        gi.prefix,
        gi.interceptors,
        gi.response_interceptors)
    end

    // Register routes with per-route interceptors only
    for r in _routes.values() do
      builder.add(
        r.method,
        r.path,
        r.factory,
        r.response_interceptors,
        r.interceptors)
    end

    // Check for tree-level errors (e.g., conflicting param or
    // wildcard names)
    match builder.first_error()
    | let err: ConfigError => return err
    end

    BuiltApplication._create(builder.build())
