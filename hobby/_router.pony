use "collections"
use stallion = "stallion"

class ref _RouterBuilder
  """

  Mutable builder for constructing a `_Router`.

  Accumulates route definitions and group interceptors into a single shared
  path tree, then freezes it into an immutable router via `build()`.
  Configuration errors (e.g., conflicting param or wildcard names) are
  accumulated in `_errors` and available via `first_error()`.
  """

  var _root: _BuildNode ref
  embed _errors: Array[String]

  new create() =>
    _root = _BuildNode
    _errors = Array[String]

  fun ref add(
    method: stallion.Method,
    path: String,
    factory: HandlerFactory,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None)
  =>
    """

    Register a route handler for a specific method and path.

    Per-route interceptors are stored in the method entry at the leaf node.
    Path-level interceptors are registered separately via `add_interceptors()`.
    """

    let normalized = _NormalizePath(path)
    let method_key: String val = method.string()
    let segments = _SplitSegments(normalized)
    _root._insert_segments(
      segments,
      0,
      method_key,
      factory,
      response_interceptors,
      interceptors,
      _errors)

  fun ref add_interceptors(path: String,
    interceptors: (Array[RequestInterceptor val] val | None),
    response_interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    """

    Register path-level interceptors on a tree node.

    Used for app-level interceptors (on the root node, path `""`) and
    group-level interceptors (on the group prefix node). Overlap detection
    happens earlier in `Application.build()` via `_ValidateGroups`.
    `_set_interceptors` concatenates as defense-in-depth.
    """

    if (interceptors is None) and (response_interceptors is None) then
      return
    end
    if path.size() == 0 then
      // Root node — app-level interceptors
      _root._set_interceptors(interceptors, response_interceptors)
      return
    end
    let normalized = _NormalizePath(path)
    let segments = _SplitSegments(normalized)
    _root._ensure_path(segments, 0, interceptors, response_interceptors)

  fun ref build(): _Router val =>
    """
    Freeze the builder into an immutable router.
    """
    _Router._create(_root.freeze(None, None))

  fun box first_error(): (ConfigError | None) =>
    """

    Return the first configuration error detected during route registration,
    or `None` if no errors were found.
    """

    if _errors.size() > 0 then
      try
        ConfigError(_errors(0)?)
      else
        _Unreachable()
        ConfigError("")
      end
    else
      None
    end

class val _Router
  """

  Immutable segment trie router with a single shared path tree.

  Handlers are keyed by HTTP method at leaf nodes. Interceptors live on
  shared path nodes and are method-independent. `lookup()` finds the matching
  handler, accumulated interceptors, and extracted parameters.
  """

  let _root: _TreeNode val

  new val _create(root: _TreeNode val) =>
    _root = root

  fun lookup(method: stallion.Method, path: String):
    (_RouteMatch | _RouteMiss | _MethodNotAllowed)
  =>
    """

    Look up a route for the given method and path.

    Returns `_RouteMatch` on success, `_RouteMiss` when the path doesn't
    exist, or `_MethodNotAllowed` when the path exists but no handler
    matches the method. For HEAD requests, automatically falls back to GET
    if no explicit HEAD handler exists.
    """

    let normalized = _NormalizePath(path)
    let method_key: String val = method.string()
    let is_head = method is stallion.HEAD
    let segments = _SplitSegments(normalized)
    _root.lookup(segments, method_key, is_head, normalized.size())

primitive _NormalizePath
  """
  Strip trailing slash (except root `/`).
  """
  fun apply(path: String): String =>
    try
      if (path.size() > 1) and (path(path.size() - 1)? == '/') then
        return path.trim(0, path.size() - 1)
      end
    else
      _Unreachable()
    end
    path

// --- Mutable build-time node ---
class ref _BuildNode
  """

  Mutable segment trie node for route construction.

  Used by `_RouterBuilder` during route registration, then frozen into a
  `_TreeNode val` for immutable lookup. Each node represents one path
  segment. Children are keyed by full segment name. Each node carries:
  - Path-level interceptors (from groups or app-level registration)
  - Method-keyed handler entries (from route registration)
  - Static children, param child, and wildcard entries for tree structure
  """

  var _interceptors: (Array[RequestInterceptor val] val | None) = None
  var _response_interceptors:
    (Array[ResponseInterceptor val] val | None) = None
  var _param_name: String = ""
  embed _children: Map[String, _BuildNode ref] =
    Map[String, _BuildNode ref]
  var _param_child: (_BuildNode ref | None) = None
  embed _method_entries: Map[String, _BuildMethodEntry ref] =
    Map[String, _BuildMethodEntry ref]
  embed _wildcard_entries: Map[String, _BuildMethodEntry ref] =
    Map[String, _BuildMethodEntry ref]
  var _wildcard_name: String = ""

  fun ref _set_interceptors(
    interceptors: (Array[RequestInterceptor val] val | None),
    response_interceptors:
      (Array[ResponseInterceptor val] val | None))
  =>
    """

    Set path-level interceptors on this node.

    Overlap detection happens earlier in `Application.build()` via
    `_ValidateGroups`, where the original full prefix strings are
    available for a clear error message. As defense-in-depth,
    concatenates rather than overwrites if interceptors already exist.
    """

    _interceptors = _ConcatInterceptors(_interceptors, interceptors)
    _response_interceptors =
      _ConcatResponseInterceptors(
        _response_interceptors,
        response_interceptors)

  fun ref _insert_segments(
    segments: Array[String] val,
    idx: USize,
    method: String,
    factory: HandlerFactory,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None),
    interceptors:
      (Array[RequestInterceptor val] val | None),
    errors: Array[String] ref)
  =>
    """
    Insert a route by walking the segment array.
    """
    if idx >= segments.size() then
      _method_entries(method) =
        _BuildMethodEntry(
          factory, interceptors, response_interceptors)
      return
    end

    let segment =
      try segments(idx)? else _Unreachable(); return end
    let first =
      try segment(0)? else _Unreachable(); return end

    if first == ':' then
      let name = segment.trim(1)
      if name.size() == 0 then
        errors.push(
          "Empty param name ':' is not allowed — " +
          "use ':name' to name the parameter.")
        return
      end
      let child =
        match _param_child
        | let existing: _BuildNode ref => existing
        else
          let c: _BuildNode ref = _BuildNode
          _param_child = c
          c
        end
      if (child._param_name.size() > 0)
        and (child._param_name != name)
      then
        errors.push(
          "Conflicting param names at the same path " +
          "position: ':" + child._param_name +
          "' vs ':" + name +
          "'. All methods at the same path must use " +
          "the same param name.")
      end
      child._param_name = name
      child._insert_segments(
        segments,
        idx + 1,
        method,
        factory,
        response_interceptors,
        interceptors,
        errors)
    elseif first == '*' then
      let name = segment.trim(1)
      if name.size() == 0 then
        errors.push(
          "Empty wildcard name '*' is not allowed — " +
          "use '*name' to name the wildcard.")
        return
      end
      if (idx + 1) < segments.size() then
        errors.push(
          "Segments after wildcard '*" + name +
          "' are not allowed — wildcards capture " +
          "the entire remainder of the path.")
        return
      end
      _wildcard_entries(method) =
        _BuildMethodEntry(
          factory,
          interceptors,
          response_interceptors)
      if (_wildcard_name.size() > 0)
        and (_wildcard_name != name)
      then
        errors.push(
          "Conflicting wildcard names at the same path " +
          "position: '*" + _wildcard_name +
          "' vs '*" + name +
          "'. All methods at the same path must use " +
          "the same wildcard name.")
      end
      _wildcard_name = name
    else
      let child =
        try _children(segment)? else
          let c: _BuildNode ref = _BuildNode
          _children(segment) = c
          c
        end
      child._insert_segments(
        segments,
        idx + 1,
        method,
        factory,
        response_interceptors,
        interceptors,
        errors)
    end

  fun ref _ensure_path(
    segments: Array[String] val,
    idx: USize,
    interceptors:
      (Array[RequestInterceptor val] val | None),
    response_interceptors:
      (Array[ResponseInterceptor val] val | None))
  =>
    """

    Traverse or create nodes to reach the given path and set interceptors.
    """

    if idx >= segments.size() then
      _set_interceptors(interceptors, response_interceptors)
      return
    end

    let segment =
      try segments(idx)? else _Unreachable(); return end
    let child =
      try _children(segment)? else
        let c: _BuildNode ref = _BuildNode
        _children(segment) = c
        c
      end
    child._ensure_path(
      segments,
      idx + 1,
      interceptors,
      response_interceptors)

  fun box freeze(
    accumulated_interceptors:
      (Array[RequestInterceptor val] val | None),
    accumulated_response_interceptors:
      (Array[ResponseInterceptor val] val | None))
    : _TreeNode val
  =>
    """

    Create an immutable deep copy of this node tree.

    Pre-computes accumulated interceptor arrays from root to each node.
    Per-route interceptors in method entries are concatenated with the
    accumulated path interceptors at freeze time, so lookup is zero-allocation.
    """

    // Accumulate this node's interceptors with ancestors'
    let new_accumulated =
      _ConcatInterceptors(accumulated_interceptors, _interceptors)
    let new_accumulated_response =
      _ConcatResponseInterceptors(
        accumulated_response_interceptors,
        _response_interceptors)

    // Freeze children — all children unconditionally receive this node's
    // accumulated interceptors (every child is at a segment boundary).
    let frozen_children: Map[String, _TreeNode val] iso =
      recover iso Map[String, _TreeNode val] end
    for (key, child) in _children.pairs() do
      frozen_children(key) =
        child.freeze(new_accumulated, new_accumulated_response)
    end

    // Param child gets full accumulated
    let frozen_param: (_TreeNode val | None) =
      match _param_child
      | let child: _BuildNode box =>
        child.freeze(new_accumulated, new_accumulated_response)
      else
        None
      end

    // Freeze method entries — concatenate accumulated path interceptors
    // with per-route interceptors
    let frozen_method_entries: Map[String, _MethodEntry val] iso =
      recover iso Map[String, _MethodEntry val] end
    for (method, entry) in _method_entries.pairs() do
      let final_interceptors =
        _ConcatInterceptors(new_accumulated, entry.interceptors)
      let final_response_interceptors =
        _ConcatResponseInterceptors(
          new_accumulated_response,
          entry.response_interceptors)
      frozen_method_entries(method) =
        _MethodEntry(
          entry.factory,
          final_interceptors,
          final_response_interceptors)
    end

    let frozen_wildcard_entries: Map[String, _MethodEntry val] iso =
      recover iso Map[String, _MethodEntry val] end
    for (method, entry) in _wildcard_entries.pairs() do
      let final_interceptors =
        _ConcatInterceptors(new_accumulated, entry.interceptors)
      let final_response_interceptors =
        _ConcatResponseInterceptors(
          new_accumulated_response,
          entry.response_interceptors)
      frozen_wildcard_entries(method) =
        _MethodEntry(
          entry.factory,
          final_interceptors,
          final_response_interceptors)
    end

    _TreeNode._create(
      new_accumulated,
      new_accumulated_response,
      _param_name,
      consume frozen_children,
      frozen_param,
      consume frozen_method_entries,
      consume frozen_wildcard_entries,
      _wildcard_name)

// --- Build-time method entry (mutable) ---
class ref _BuildMethodEntry
  """

  Mutable method entry during tree construction.

  Holds the handler factory and per-route interceptors before freeze-time
  concatenation with accumulated path interceptors.
  """

  let factory: HandlerFactory
  let interceptors: (Array[RequestInterceptor val] val | None)
  let response_interceptors:
    (Array[ResponseInterceptor val] val | None)

  new ref create(
    factory': HandlerFactory,
    interceptors':
      (Array[RequestInterceptor val] val | None),
    response_interceptors':
      (Array[ResponseInterceptor val] val | None))
  =>
    factory = factory'
    interceptors = interceptors'
    response_interceptors = response_interceptors'

// --- Immutable lookup node ---
class val _TreeNode
  """

  Immutable segment trie node for route lookup.

  Produced by freezing a `_BuildNode`. Each node stores pre-computed
  accumulated interceptors (from root through this node). In a segment
  trie, every child is at a segment boundary, so the accumulated
  interceptors propagate unconditionally to all children.

  Method entries store final interceptor arrays (accumulated + per-route,
  concatenated at freeze time). Lookup is zero-allocation for both hits
  and misses.
  """

  let _accumulated_interceptors:
    (Array[RequestInterceptor val] val | None)
  let _accumulated_response_interceptors:
    (Array[ResponseInterceptor val] val | None)
  let _param_name: String
  let _children: Map[String, _TreeNode val] val
  let _param_child: (_TreeNode val | None)
  let _method_entries: Map[String, _MethodEntry val] val
  let _wildcard_entries: Map[String, _MethodEntry val] val
  let _wildcard_name: String

  new val _create(
    accumulated_interceptors':
      (Array[RequestInterceptor val] val | None),
    accumulated_response_interceptors':
      (Array[ResponseInterceptor val] val | None),
    param_name: String,
    children: Map[String, _TreeNode val] iso,
    param_child: (_TreeNode val | None),
    method_entries: Map[String, _MethodEntry val] iso,
    wildcard_entries: Map[String, _MethodEntry val] iso,
    wildcard_name: String)
  =>
    _accumulated_interceptors = accumulated_interceptors'
    _accumulated_response_interceptors =
      accumulated_response_interceptors'
    _param_name = param_name
    _children = consume children
    _param_child = param_child
    _method_entries = consume method_entries
    _wildcard_entries = consume wildcard_entries
    _wildcard_name = wildcard_name

  fun lookup(
    segments: Array[String] val,
    method_key: String,
    is_head: Bool,
    path_size: USize)
    : (_RouteMatch | _RouteMiss | _MethodNotAllowed)
  =>
    """
    Find a matching route for the given path and method.
    """
    match \exhaustive\ _lookup(
      segments, 0, method_key, is_head, path_size)
    | (let entry: _MethodEntry val,
      let p: Array[(String, String)] val) =>
      let frozen: Map[String, String] val =
        recover val
          let m = Map[String, String]
          for (k, v) in p.values() do
            m(k) = v
          end
          m
        end
      _RouteMatch(
        entry.factory,
        entry.response_interceptors,
        entry.interceptors,
        frozen)
    | let miss: _RouteMiss => miss
    | let na: _MethodNotAllowed => na
    end

  fun _lookup(
    segments: Array[String] val,
    idx: USize,
    method_key: String,
    is_head: Bool,
    path_size: USize)
    : ((_MethodEntry val, Array[(String, String)] val) |
      _RouteMiss | _MethodNotAllowed)
  =>
    """

    Recursive lookup returning method entry and accumulated params on hit,
    `_RouteMiss` when the path doesn't exist, or `_MethodNotAllowed` when
    the path exists but no handler matches the requested method.

    Params are built bottom-up: the leaf returns an empty val array, and each
    param level prepends its parameter to the child's val result.

    When multiple priority branches (static > param > wildcard) each return
    `_MethodNotAllowed`, this function merges their allowed methods into a
    single `Allow` header. The first 405's interceptors are kept — they come
    from the highest-priority (most specific) branch. `_resolve_or_405`
    reports methods from a single entries map; this function merges across
    calls.
    """

    if idx >= segments.size() then
      match _resolve_or_405(
        method_key, is_head, _method_entries)
      | let entry: _MethodEntry val =>
        return (entry, _EmptyParams())
      | let na: _MethodNotAllowed =>
        return na
      end
      return _RouteMiss(
        _accumulated_response_interceptors,
        _accumulated_interceptors)
    end

    // Try all branches in priority order (static > param > wildcard) for
    // the requested method. A match from any branch returns immediately.
    // Misses and method-not-allowed results are saved — we only decide
    // 404 vs 405 after all branches are exhausted.
    var deepest_miss: (_RouteMiss | None) = None
    var method_not_allowed: (_MethodNotAllowed | None) = None
    var merged_methods: Array[String] iso =
      recover iso Array[String] end

    // Try static children first (highest priority)
    try
      let segment = segments(idx)?
      try
        let child = _children(segment)?
        match \exhaustive\ child._lookup(
          segments,
          idx + 1,
          method_key,
          is_head,
          path_size)
        | (let entry: _MethodEntry val,
          let p: Array[(String, String)] val) =>
          return (entry, p)
        | let na: _MethodNotAllowed =>
          if method_not_allowed is None then
            method_not_allowed = na
          end
          for m in na.allowed_methods.values() do
            if not merged_methods.contains(
              m, {(l, r) => l == r })
            then
              merged_methods.push(m)
            end
          end
        | let miss: _RouteMiss =>
          deepest_miss = miss
        end
      end
    else
      _Unreachable()
    end

    // Try parameter child (second priority)
    match _param_child
    | let child: _TreeNode val =>
      try
        let segment = segments(idx)?
        // _SplitSegments never produces empty segments,
        // but guard defensively
        if segment.size() > 0 then
          match \exhaustive\ child._lookup(
            segments,
            idx + 1,
            method_key,
            is_head,
            path_size)
          | (let entry: _MethodEntry val,
            let child_params:
              Array[(String, String)] val) =>
            let with_param:
              Array[(String, String)] val
            =
              recover val
                let a = Array[(String, String)]
                a.push((child._param_name, segment))
                for (k, v) in child_params.values() do
                  a.push((k, v))
                end
                a
              end
            return (entry, with_param)
          | let na: _MethodNotAllowed =>
            if method_not_allowed is None then
              method_not_allowed = na
            end
            for m in na.allowed_methods.values() do
              if not merged_methods.contains(
                m, {(l, r) => l == r })
              then
                merged_methods.push(m)
              end
            end
          | let miss: _RouteMiss =>
            // Keep whichever miss traversed deeper
            // (has richer interceptors).
            match deepest_miss
            | let prev: _RouteMiss =>
              if miss._interceptor_count()
                > prev._interceptor_count()
              then
                deepest_miss = miss
              end
            else
              deepest_miss = miss
            end
          end
        end
      else
        _Unreachable()
      end
    end

    // Try wildcard (lowest priority)
    match _resolve_or_405(
      method_key, is_head, _wildcard_entries)
    | let entry: _MethodEntry val =>
      let remainder =
        _JoinRemainingSegments(segments, idx, path_size)
      let wildcard_params:
        Array[(String, String)] val
      =
        recover val
          Array[(String, String)]
            .> push((_wildcard_name, remainder))
        end
      return (entry, wildcard_params)
    | let na: _MethodNotAllowed =>
      if method_not_allowed is None then
        method_not_allowed = na
      end
      for m in na.allowed_methods.values() do
        if not merged_methods.contains(
          m, {(l, r) => l == r })
        then
          merged_methods.push(m)
        end
      end
    end

    // All branches exhausted. Priority: 405 > deepest miss > fresh miss.
    // 405 means the path exists (for some method), which is more specific
    // than a miss (path doesn't exist at all). When multiple branches
    // returned 405, merged_methods has the union; use it if it's larger
    // than the first 405's list.
    match method_not_allowed
    | let na: _MethodNotAllowed =>
      if merged_methods.size() > na.allowed_methods.size() then
        return _MethodNotAllowed(
          consume merged_methods,
          na.response_interceptors,
          na.interceptors)
      else
        return na
      end
    end

    match deepest_miss
    | let miss: _RouteMiss => miss
    else
      _RouteMiss(
        _accumulated_response_interceptors,
        _accumulated_interceptors)
    end

  fun _resolve_or_405(
    method_key: String,
    is_head: Bool,
    entries: Map[String, _MethodEntry val] val)
    : (_MethodEntry val | _MethodNotAllowed | None)
  =>
    """

    Try to resolve a method entry from the given entries map.

    Returns the entry on match, `_MethodNotAllowed` if the map has entries
    but not for this method (with HEAD→GET fallback for HEAD requests),
    or `None` if the map is empty. The `_MethodNotAllowed` carries only
    the methods from this specific entries map — exact-path and wildcard
    entries are never mixed at this level. `_lookup` merges methods across
    multiple `_resolve_or_405` calls when multiple priority branches each
    return 405.
    """

    try
      return entries(method_key)?
    end
    if is_head then
      try
        return entries("GET")?
      end
    end
    if entries.size() > 0 then
      let allowed: Array[String] val =
        recover val
          let methods = Array[String]
          var has_get = false
          for k in entries.keys() do
            methods.push(k)
            if k == "GET" then has_get = true end
          end
          if has_get then
            var has_head = false
            for m in methods.values() do
              if m == "HEAD" then
                has_head = true; break
              end
            end
            if not has_head then
              methods.push("HEAD")
            end
          end
          methods
        end
      _MethodNotAllowed(
        allowed,
        _accumulated_response_interceptors,
        _accumulated_interceptors)
    else
      None
    end

// --- Shared constants ---
primitive _EmptyParams
  """
  Empty params array returned at leaf nodes.
  """
  fun apply(): Array[(String, String)] val =>
    recover val Array[(String, String)] end
