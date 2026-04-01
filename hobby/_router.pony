use "collections"
use stallion = "stallion"

class ref _RouterBuilder
  """
  Mutable builder for constructing a `_Router`.

  Accumulates route definitions and group interceptors into a single shared
  path tree, then freezes it into an immutable router via `build()`.
  Configuration errors (e.g., conflicting param names) are accumulated in
  `_errors` and available via `first_error()`.
  """
  var _root: _BuildNode ref
  embed _errors: Array[String]

  new create() =>
    _root = _BuildNode
    _errors = Array[String]

  fun ref add(method: stallion.Method, path: String,
    factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None,
    interceptors: (Array[RequestInterceptor val] val | None) = None)
  =>
    """
    Register a route handler for a specific method and path.

    Per-route interceptors are stored in the method entry at the leaf node.
    Path-level interceptors are registered separately via `add_interceptors()`.
    """
    let normalized = _NormalizePath(path)
    let method_key: String val = method.string()
    _root.insert(normalized, method_key, factory, response_interceptors,
      interceptors, _errors)

  fun ref add_interceptors(path: String,
    interceptors: (Array[RequestInterceptor val] val | None),
    response_interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    """
    Register path-level interceptors on a tree node.

    Used for app-level interceptors (on the root node, path `""`) and
    group-level interceptors (on the group prefix node). Overlap detection
    happens earlier in `Application.serve()` via `_ValidateGroups`.
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
    _root._ensure_path(normalized, 0, interceptors, response_interceptors)

  fun ref build(): _Router val =>
    """Freeze the builder into an immutable router."""
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
  Immutable radix tree router with a single shared path tree.

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
    _root.lookup(normalized, method_key, is_head)

primitive _NormalizePath
  """Strip trailing slash (except root `/`)."""
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
  Mutable radix tree node for route construction.

  Used by `_RouterBuilder` during route registration, then frozen into a
  `_TreeNode val` for immutable lookup. Each node carries:
  - Path-level interceptors (from groups or app-level registration)
  - Method-keyed handler entries (from route registration)
  - Static children and param/wildcard children for tree structure
  """
  var _prefix: String = ""
  var _interceptors: (Array[RequestInterceptor val] val | None) = None
  var _response_interceptors: (Array[ResponseInterceptor val] val | None) = None
  var _param_name: String = ""
  embed _children: Map[U8, _BuildNode ref] = Map[U8, _BuildNode ref]
  var _param_child: (_BuildNode ref | None) = None
  embed _method_entries: Map[String, _BuildMethodEntry ref] =
    Map[String, _BuildMethodEntry ref]
  embed _wildcard_entries: Map[String, _BuildMethodEntry ref] =
    Map[String, _BuildMethodEntry ref]
  var _wildcard_name: String = ""

  new create(prefix: String = "") =>
    _prefix = prefix

  fun ref _set_interceptors(
    interceptors: (Array[RequestInterceptor val] val | None),
    response_interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    """
    Set path-level interceptors on this node.

    Overlap detection happens earlier in `Application.serve()` via
    `_ValidateGroups`, where the original full prefix strings are
    available for a clear error message. As defense-in-depth,
    concatenates rather than overwrites if interceptors already exist.
    """
    _interceptors = _ConcatInterceptors(_interceptors, interceptors)
    _response_interceptors =
      _ConcatResponseInterceptors(_response_interceptors,
        response_interceptors)

  fun ref insert(path: String, method: String, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None),
    errors: Array[String] ref)
  =>
    """Insert a route path into this subtree."""
    _insert(path, 0, method, factory, response_interceptors, interceptors,
      errors)

  fun ref _ensure_path(path: String, offset: USize,
    interceptors: (Array[RequestInterceptor val] val | None),
    response_interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    """
    Traverse or create nodes to reach the given path and set interceptors.

    Uses the same prefix-matching logic as insert to handle post-split node
    structure correctly.
    """
    if offset >= path.size() then
      _set_interceptors(interceptors, response_interceptors)
      return
    end

    try
      let c = path(offset)?
      // Only handle static paths for group interceptors (no : or * in group prefixes)
      match try _children(c)? end
      | let child: _BuildNode ref =>
        let common = _Paths.common_prefix_len(child._prefix,
          path.trim(offset))
        if common == child._prefix.size() then
          child._ensure_path(path, offset + common, interceptors,
            response_interceptors)
        else
          // Split the child node at the divergence point
          let new_parent = _BuildNode(child._prefix.trim(0, common))
          let old_suffix = child._prefix.trim(common)
          child._prefix = old_suffix
          try
            new_parent._children(old_suffix(0)?) = child
          else
            _Unreachable()
          end
          if (offset + common) >= path.size() then
            new_parent._set_interceptors(interceptors, response_interceptors)
          else
            new_parent._ensure_path(path, offset + common, interceptors,
              response_interceptors)
          end
          _children(c) = new_parent
        end
      else
        // No existing child — create the path
        let remaining = path.trim(offset)
        let child = _BuildNode(remaining)
        child._set_interceptors(interceptors, response_interceptors)
        _children(c) = child
      end
    else
      _Unreachable()
    end

  fun ref _insert(path: String, offset: USize, method: String,
    factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None),
    errors: Array[String] ref)
  =>
    if offset >= path.size() then
      _method_entries(method) = _BuildMethodEntry(factory,
        interceptors, response_interceptors)
      return
    end

    try
      let c = path(offset)?
      if c == ':' then
        _insert_param(path, offset, method, factory, response_interceptors,
          interceptors, errors)
      elseif c == '*' then
        _wildcard_entries(method) = _BuildMethodEntry(factory,
          interceptors, response_interceptors)
        _wildcard_name = path.trim(offset + 1)
      else
        _insert_static(path, offset, method, factory, response_interceptors,
          interceptors, errors)
      end
    else
      _Unreachable()
    end

  fun ref _insert_param(path: String, offset: USize, method: String,
    factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None),
    errors: Array[String] ref)
  =>
    let name_end = _Paths.find_char(path, '/', offset + 1)
    let name = path.trim(offset + 1, name_end)
    let child = match _param_child
    | let existing: _BuildNode ref => existing
    else
      let c = _BuildNode
      _param_child = c
      c
    end
    if (child._param_name.size() > 0) and (child._param_name != name) then
      errors.push(
        "Conflicting param names at the same path position: ':" +
        child._param_name + "' vs ':" + name +
        "'. All methods at the same path must use the same param name.")
    end
    child._param_name = name
    if name_end >= path.size() then
      child._method_entries(method) = _BuildMethodEntry(factory,
        interceptors, response_interceptors)
    else
      child._insert(path, name_end, method, factory, response_interceptors,
        interceptors, errors)
    end

  fun ref _insert_static(path: String, offset: USize, method: String,
    factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None),
    errors: Array[String] ref)
  =>
    try
      let c = path(offset)?
      match try _children(c)? end
      | let child: _BuildNode ref =>
        let common = _Paths.common_prefix_len(child._prefix,
          path.trim(offset))
        if common == child._prefix.size() then
          child._insert(path, offset + common, method, factory,
            response_interceptors, interceptors, errors)
        else
          // Split the child node at the divergence point
          let new_parent = _BuildNode(child._prefix.trim(0, common))
          let old_suffix = child._prefix.trim(common)
          child._prefix = old_suffix
          try
            new_parent._children(old_suffix(0)?) = child
          else
            _Unreachable()
          end
          // Route through _insert so special characters (`:`, `*`) in the
          // remaining suffix are parsed instead of stored as literal prefix.
          new_parent._insert(path, offset + common, method, factory,
            response_interceptors, interceptors, errors)
          _children(c) = new_parent
        end
      else
        // No existing child for this character
        let remaining = path.trim(offset)
        let special = _Paths.find_special(remaining)
        if special < remaining.size() then
          let child = _BuildNode(remaining.trim(0, special))
          child._insert(path, offset + special, method, factory,
            response_interceptors, interceptors, errors)
          _children(c) = child
        else
          let child = _BuildNode(remaining)
          child._method_entries(method) = _BuildMethodEntry(factory,
            interceptors, response_interceptors)
          _children(c) = child
        end
      end
    else
      _Unreachable()
    end

  fun box freeze(
    parent_interceptors: (Array[RequestInterceptor val] val | None),
    parent_response_interceptors:
      (Array[ResponseInterceptor val] val | None))
    : _TreeNode val
  =>
    """
    Create an immutable deep copy of this node tree.

    Pre-computes accumulated interceptor arrays from root to each node.
    Per-route interceptors in method entries are concatenated with the
    accumulated path interceptors at freeze time, so lookup is zero-allocation.
    """
    // Accumulate this node's interceptors with parent's
    let accumulated_interceptors =
      _ConcatInterceptors(parent_interceptors, _interceptors)
    let accumulated_response_interceptors =
      _ConcatResponseInterceptors(parent_response_interceptors,
        _response_interceptors)

    // Freeze children — only propagate this node's interceptors to sub-path
    // children (key == '/'). Children at other keys share a character prefix
    // but are in different path segments (e.g., /api-docs is not under /api).
    let frozen_children: Array[(U8, _TreeNode val)] iso =
      recover iso Array[(U8, _TreeNode val)] end
    for (key, child) in _children.pairs() do
      if key == '/' then
        frozen_children.push((key, child.freeze(accumulated_interceptors,
          accumulated_response_interceptors)))
      else
        frozen_children.push((key, child.freeze(parent_interceptors,
          parent_response_interceptors)))
      end
    end
    // Param child is always a sub-segment — gets full accumulated
    let frozen_param: (_TreeNode val | None) = match _param_child
    | let child: _BuildNode box =>
      child.freeze(accumulated_interceptors, accumulated_response_interceptors)
    else
      None
    end

    // Freeze method entries — concatenate accumulated path interceptors
    // with per-route interceptors
    let frozen_method_entries: Map[String, _MethodEntry val] iso =
      recover iso Map[String, _MethodEntry val] end
    for (method, entry) in _method_entries.pairs() do
      let final_interceptors =
        _ConcatInterceptors(accumulated_interceptors, entry.interceptors)
      let final_response_interceptors =
        _ConcatResponseInterceptors(accumulated_response_interceptors,
          entry.response_interceptors)
      frozen_method_entries(method) = _MethodEntry(entry.factory,
        final_interceptors, final_response_interceptors)
    end

    let frozen_wildcard_entries: Map[String, _MethodEntry val] iso =
      recover iso Map[String, _MethodEntry val] end
    for (method, entry) in _wildcard_entries.pairs() do
      let final_interceptors =
        _ConcatInterceptors(accumulated_interceptors, entry.interceptors)
      let final_response_interceptors =
        _ConcatResponseInterceptors(accumulated_response_interceptors,
          entry.response_interceptors)
      frozen_wildcard_entries(method) = _MethodEntry(entry.factory,
        final_interceptors, final_response_interceptors)
    end

    _TreeNode._create(_prefix,
      parent_interceptors, parent_response_interceptors,
      accumulated_interceptors, accumulated_response_interceptors,
      _param_name, consume frozen_children, frozen_param,
      consume frozen_method_entries, consume frozen_wildcard_entries,
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
  let response_interceptors: (Array[ResponseInterceptor val] val | None)

  new ref create(factory': HandlerFactory,
    interceptors': (Array[RequestInterceptor val] val | None),
    response_interceptors': (Array[ResponseInterceptor val] val | None))
  =>
    factory = factory'
    interceptors = interceptors'
    response_interceptors = response_interceptors'

// --- Immutable lookup node ---

class val _TreeNode
  """
  Immutable radix tree node for route lookup.

  Produced by freezing a `_BuildNode`. Each node stores two levels of
  pre-computed interceptors: parent-level (from ancestors only) and
  accumulated (parent + own). This separation is needed because
  interceptors are segment-scoped — a node's own interceptors only apply
  to sub-paths (children at '/'), not to sibling routes that share a
  character prefix (children at other keys like '-').

  Method entries store final interceptor arrays (accumulated + per-route,
  concatenated at freeze time). Lookup is zero-allocation for both hits
  and misses.
  """
  let _prefix: String
  // Interceptors from ancestor nodes only — for misses on sibling paths
  let _parent_interceptors:
    (Array[RequestInterceptor val] val | None)
  let _parent_response_interceptors:
    (Array[ResponseInterceptor val] val | None)
  // Interceptors accumulated through this node — for sub-path matches/misses
  let _accumulated_interceptors:
    (Array[RequestInterceptor val] val | None)
  let _accumulated_response_interceptors:
    (Array[ResponseInterceptor val] val | None)
  let _param_name: String
  let _children: Array[(U8, _TreeNode val)] val
  let _param_child: (_TreeNode val | None)
  let _method_entries: Map[String, _MethodEntry val] val
  let _wildcard_entries: Map[String, _MethodEntry val] val
  let _wildcard_name: String

  new val _create(prefix: String,
    parent_interceptors':
      (Array[RequestInterceptor val] val | None),
    parent_response_interceptors':
      (Array[ResponseInterceptor val] val | None),
    accumulated_interceptors':
      (Array[RequestInterceptor val] val | None),
    accumulated_response_interceptors':
      (Array[ResponseInterceptor val] val | None),
    param_name: String,
    children: Array[(U8, _TreeNode val)] iso,
    param_child: (_TreeNode val | None),
    method_entries: Map[String, _MethodEntry val] iso,
    wildcard_entries: Map[String, _MethodEntry val] iso,
    wildcard_name: String)
  =>
    _prefix = prefix
    _parent_interceptors = parent_interceptors'
    _parent_response_interceptors = parent_response_interceptors'
    _accumulated_interceptors = accumulated_interceptors'
    _accumulated_response_interceptors = accumulated_response_interceptors'
    _param_name = param_name
    _children = consume children
    _param_child = param_child
    _method_entries = consume method_entries
    _wildcard_entries = consume wildcard_entries
    _wildcard_name = wildcard_name

  fun lookup(path: String, method_key: String, is_head: Bool):
    (_RouteMatch | _RouteMiss | _MethodNotAllowed)
  =>
    """Find a matching route for the given path and method."""
    match _lookup(path, 0, method_key, is_head)
    | (let entry: _MethodEntry val, let p: Array[(String, String)] val) =>
      let frozen: Map[String, String] val = recover val
        let m = Map[String, String]
        for (k, v) in p.values() do
          m(k) = v
        end
        m
      end
      _RouteMatch(entry.factory, entry.response_interceptors,
        entry.interceptors, frozen)
    | let miss: _RouteMiss => miss
    | let na: _MethodNotAllowed => na
    end

  fun _lookup(path: String, offset: USize, method_key: String,
    is_head: Bool):
    ((_MethodEntry val, Array[(String, String)] val) |
      _RouteMiss | _MethodNotAllowed)
  =>
    """
    Recursive lookup returning method entry and accumulated params on hit,
    `_RouteMiss` when the path doesn't exist, or `_MethodNotAllowed` when
    the path exists but no handler matches the requested method.

    Params are built bottom-up: the leaf returns an empty val array, and each
    param level prepends its parameter to the child's val result.
    """
    if offset >= path.size() then
      match _resolve_or_405(method_key, is_head, _method_entries)
      | let entry: _MethodEntry val =>
        return (entry, _EmptyParams())
      | let na: _MethodNotAllowed =>
        return na
      end
      return _RouteMiss(_accumulated_response_interceptors,
        _accumulated_interceptors)
    end

    // Try all branches in priority order (static > param > wildcard) for
    // the requested method. A match from any branch returns immediately.
    // Misses and method-not-allowed results are saved — we only decide
    // 404 vs 405 after all branches are exhausted.
    var deepest_miss: (_RouteMiss | None) = None
    var method_not_allowed: (_MethodNotAllowed | None) = None

    // Try static children first (highest priority)
    try
      let c = path(offset)?
      for (key, child) in _children.values() do
        if key == c then
          if _Paths.starts_with(path, offset, child._prefix) then
            match child._lookup(path, offset + child._prefix.size(),
              method_key, is_head)
            | (let entry: _MethodEntry val,
               let p: Array[(String, String)] val) =>
              return (entry, p)
            | let na: _MethodNotAllowed =>
              // Save but continue — a lower-priority branch may match
              if method_not_allowed is None then
                method_not_allowed = na
              end
            | let miss: _RouteMiss =>
              deepest_miss = miss
            end
          end
          break
        end
      end
    else
      _Unreachable()
    end

    // Try parameter child (second priority)
    match _param_child
    | let child: _TreeNode val =>
      let value_end = _Paths.find_char(path, '/', offset)
      if value_end > offset then
        let value = path.trim(offset, value_end)
        match child._lookup(path, value_end, method_key, is_head)
        | (let entry: _MethodEntry val,
           let child_params: Array[(String, String)] val) =>
          let with_param: Array[(String, String)] val = recover val
            let a = Array[(String, String)]
            a.push((child._param_name, value))
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
        | let miss: _RouteMiss =>
          // Keep whichever miss traversed deeper (has richer interceptors).
          match deepest_miss
          | let prev: _RouteMiss =>
            if miss._interceptor_count() > prev._interceptor_count() then
              deepest_miss = miss
            end
          else
            deepest_miss = miss
          end
        end
      end
    end

    // Try wildcard (lowest priority)
    match _resolve_or_405(method_key, is_head, _wildcard_entries)
    | let entry: _MethodEntry val =>
      let remainder = path.trim(offset)
      let wildcard_params: Array[(String, String)] val = recover val
        let a = Array[(String, String)]
        a.push((_wildcard_name, remainder))
        a
      end
      return (entry, wildcard_params)
    | let na: _MethodNotAllowed =>
      if method_not_allowed is None then
        method_not_allowed = na
      end
    end

    // All branches exhausted. Priority: 405 > deepest miss > fresh miss.
    // 405 means the path exists (for some method), which is more specific
    // than a miss (path doesn't exist at all).
    match method_not_allowed
    | let na: _MethodNotAllowed => return na
    end

    // Interceptor selection for the miss depends on whether the remaining
    // path is a sub-path (starts with '/') or a sibling route sharing a
    // character prefix (starts with non-'/'). Sub-paths get accumulated
    // interceptors; siblings get parent-only interceptors.
    match deepest_miss
    | let miss: _RouteMiss => miss
    else
      let at_segment_boundary = try path(offset)? == '/' else true end
      if at_segment_boundary then
        _RouteMiss(_accumulated_response_interceptors,
          _accumulated_interceptors)
      else
        _RouteMiss(_parent_response_interceptors,
          _parent_interceptors)
      end
    end

  fun _resolve_or_405(method_key: String, is_head: Bool,
    entries: Map[String, _MethodEntry val] val)
    : (_MethodEntry val | _MethodNotAllowed | None)
  =>
    """
    Try to resolve a method entry from the given entries map.

    Returns the entry on match, `_MethodNotAllowed` if the map has entries
    but not for this method (with HEAD→GET fallback for HEAD requests),
    or `None` if the map is empty. The `_MethodNotAllowed` carries only
    the methods from this specific map — exact-path and wildcard entries
    are never mixed.
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
      let allowed: Array[String] val = recover val
        let methods = Array[String]
        var has_get = false
        for k in entries.keys() do
          methods.push(k)
          if k == "GET" then has_get = true end
        end
        if has_get then
          var has_head = false
          for m in methods.values() do
            if m == "HEAD" then has_head = true; break end
          end
          if not has_head then methods.push("HEAD") end
        end
        methods
      end
      _MethodNotAllowed(allowed,
        _accumulated_response_interceptors, _accumulated_interceptors)
    else
      None
    end

// --- Shared constants ---

primitive _EmptyParams
  """Empty params array for leaf returns — avoids allocation at each recursion level."""
  fun apply(): Array[(String, String)] val =>
    recover val Array[(String, String)] end

// --- Path utilities ---

primitive _Paths
  fun find_char(s: String box, c: U8, from: USize = 0): USize =>
    """Find the first occurrence of `c` in `s` starting at `from`."""
    var i = from
    try
      while i < s.size() do
        if s(i)? == c then return i end
        i = i + 1
      end
    else
      _Unreachable()
    end
    s.size()

  fun find_special(s: String box): USize =>
    """Find the first `:` or `*` in `s`."""
    var i: USize = 0
    try
      while i < s.size() do
        let c = s(i)?
        if (c == ':') or (c == '*') then return i end
        i = i + 1
      end
    else
      _Unreachable()
    end
    s.size()

  fun common_prefix_len(a: String box, b: String box): USize =>
    var i: USize = 0
    let limit = a.size().min(b.size())
    try
      while i < limit do
        if a(i)? != b(i)? then break end
        i = i + 1
      end
    else
      _Unreachable()
    end
    i

  fun starts_with(path: String box, offset: USize,
    prefix: String box): Bool
  =>
    """Check if `path` at `offset` starts with `prefix`."""
    if (offset + prefix.size()) > path.size() then
      return false
    end
    var i: USize = 0
    try
      while i < prefix.size() do
        if path(offset + i)? != prefix(i)? then return false end
        i = i + 1
      end
    else
      _Unreachable()
    end
    true
