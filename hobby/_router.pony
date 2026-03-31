use "collections"
use stallion = "stallion"

class ref _RouterBuilder
  """
  Mutable builder for constructing a `_Router`.

  Accumulates route definitions and builds an immutable router via `build()`.
  """
  embed _trees: Map[String, _BuildNode ref]

  new create() =>
    _trees = Map[String, _BuildNode ref]

  fun ref add(method: stallion.Method, path: String, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None,
    interceptors: (Array[RequestInterceptor val] val | None) = None)
  =>
    """Register a route. The path must start with `/`."""
    let normalized = _NormalizePath(path)
    let method_key: String val = method.string()
    let tree = try
      _trees(method_key)?
    else
      let node = _BuildNode
      _trees(method_key) = node
      node
    end
    tree.insert(normalized, factory, response_interceptors, interceptors)

  fun ref build(): _Router val =>
    """Freeze the builder into an immutable router."""
    let frozen_trees: Map[String, _TreeNode val] iso =
      recover iso Map[String, _TreeNode val] end
    for (method, node) in _trees.pairs() do
      frozen_trees(method) = node.freeze()
    end
    _Router._create(consume frozen_trees)

class val _Router
  """
  Immutable radix tree router.

  One tree per HTTP method. `lookup()` finds the matching handler, response
  interceptors, request interceptors, and extracted parameters for a given
  method and path.
  """
  let _trees: Map[String, _TreeNode val] val

  new val _create(trees: Map[String, _TreeNode val] iso) =>
    _trees = consume trees

  fun lookup(method: stallion.Method, path: String): (_RouteMatch | None) =>
    """
    Look up a route for the given method and path.

    Returns a `_RouteMatch` with handler, response interceptors, request
    interceptors, and extracted parameters, or `None` if no route matches.
    """
    let normalized = _NormalizePath(path)
    let method_key: String val = method.string()
    try
      _trees(method_key)?.lookup(normalized)
    else
      None
    end

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
  `_TreeNode val` for immutable lookup.
  """
  var _prefix: String = ""
  var _factory: (HandlerFactory | None) = None
  var _response_interceptors: (Array[ResponseInterceptor val] val | None) = None
  var _interceptors: (Array[RequestInterceptor val] val | None) = None
  var _param_name: String = ""
  embed _children: Map[U8, _BuildNode ref] = Map[U8, _BuildNode ref]
  var _param_child: (_BuildNode ref | None) = None
  var _wildcard_factory: (HandlerFactory | None) = None
  var _wildcard_response_interceptors:
    (Array[ResponseInterceptor val] val | None) = None
  var _wildcard_interceptors: (Array[RequestInterceptor val] val | None) = None
  var _wildcard_name: String = ""

  new create(prefix: String = "") =>
    _prefix = prefix

  fun ref insert(path: String, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None))
  =>
    """Insert a route path into this subtree."""
    _insert(path, 0, factory, response_interceptors, interceptors)

  fun ref _insert(path: String, offset: USize, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None))
  =>
    if offset >= path.size() then
      _factory = factory
      _response_interceptors = response_interceptors
      _interceptors = interceptors
      return
    end

    try
      let c = path(offset)?
      if c == ':' then
        _insert_param(path, offset, factory, response_interceptors, interceptors)
      elseif c == '*' then
        _wildcard_factory = factory
        _wildcard_response_interceptors = response_interceptors
        _wildcard_interceptors = interceptors
        _wildcard_name = path.trim(offset + 1)
      else
        _insert_static(path, offset, factory, response_interceptors,
          interceptors)
      end
    else
      _Unreachable()
    end

  fun ref _insert_param(path: String, offset: USize, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None))
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
    child._param_name = name
    if name_end >= path.size() then
      child._factory = factory
      child._response_interceptors = response_interceptors
      child._interceptors = interceptors
    else
      child._insert(path, name_end, factory, response_interceptors, interceptors)
    end

  fun ref _insert_static(path: String, offset: USize, factory: HandlerFactory,
    response_interceptors: (Array[ResponseInterceptor val] val | None),
    interceptors: (Array[RequestInterceptor val] val | None))
  =>
    try
      let c = path(offset)?
      match try _children(c)? end
      | let child: _BuildNode ref =>
        let common = _Paths.common_prefix_len(child._prefix,
          path.trim(offset))
        if common == child._prefix.size() then
          child._insert(path, offset + common, factory, response_interceptors,
            interceptors)
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
          new_parent._insert(path, offset + common, factory,
            response_interceptors, interceptors)
          _children(c) = new_parent
        end
      else
        // No existing child for this character
        let remaining = path.trim(offset)
        let special = _Paths.find_special(remaining)
        if special < remaining.size() then
          let child = _BuildNode(remaining.trim(0, special))
          child._insert(path, offset + special, factory, response_interceptors,
            interceptors)
          _children(c) = child
        else
          let child = _BuildNode(remaining)
          child._factory = factory
          child._response_interceptors = response_interceptors
          child._interceptors = interceptors
          _children(c) = child
        end
      end
    else
      _Unreachable()
    end

  fun box freeze(): _TreeNode val =>
    """Create an immutable deep copy of this node tree."""
    let frozen_children: Array[(U8, _TreeNode val)] iso =
      recover iso Array[(U8, _TreeNode val)] end
    for (key, child) in _children.pairs() do
      frozen_children.push((key, child.freeze()))
    end
    let frozen_param: (_TreeNode val | None) = match _param_child
    | let child: _BuildNode box => child.freeze()
    else
      None
    end
    _TreeNode._create(_prefix, _factory, _response_interceptors, _interceptors,
      _param_name, consume frozen_children, frozen_param, _wildcard_factory,
      _wildcard_response_interceptors, _wildcard_interceptors, _wildcard_name)

// --- Immutable lookup node ---

class val _TreeNode
  """
  Immutable radix tree node for route lookup.

  Produced by freezing a `_BuildNode`. Supports `lookup()` to find a matching
  handler, response interceptors, request interceptors, and parameters for a
  given path.
  """
  let _prefix: String
  let _factory: (HandlerFactory | None)
  let _response_interceptors: (Array[ResponseInterceptor val] val | None)
  let _interceptors: (Array[RequestInterceptor val] val | None)
  let _param_name: String
  let _children: Array[(U8, _TreeNode val)] val
  let _param_child: (_TreeNode val | None)
  let _wildcard_factory: (HandlerFactory | None)
  let _wildcard_response_interceptors:
    (Array[ResponseInterceptor val] val | None)
  let _wildcard_interceptors: (Array[RequestInterceptor val] val | None)
  let _wildcard_name: String

  new val _create(prefix: String, factory': (HandlerFactory | None),
    response_interceptors': (Array[ResponseInterceptor val] val | None),
    interceptors': (Array[RequestInterceptor val] val | None),
    param_name: String,
    children: Array[(U8, _TreeNode val)] iso,
    param_child: (_TreeNode val | None),
    wildcard_factory': (HandlerFactory | None),
    wildcard_response_interceptors':
      (Array[ResponseInterceptor val] val | None),
    wildcard_interceptors': (Array[RequestInterceptor val] val | None),
    wildcard_name: String)
  =>
    _prefix = prefix
    _factory = factory'
    _response_interceptors = response_interceptors'
    _interceptors = interceptors'
    _param_name = param_name
    _children = consume children
    _param_child = param_child
    _wildcard_factory = wildcard_factory'
    _wildcard_response_interceptors = wildcard_response_interceptors'
    _wildcard_interceptors = wildcard_interceptors'
    _wildcard_name = wildcard_name

  fun lookup(path: String): (_RouteMatch | None) =>
    """Find a matching route for the given path."""
    match _lookup(path, 0)
    | (let f: HandlerFactory,
       let ri: (Array[ResponseInterceptor val] val | None),
       let gs: (Array[RequestInterceptor val] val | None),
       let p: Array[(String, String)] val) =>
      let frozen: Map[String, String] val = recover val
        let m = Map[String, String]
        for (k, v) in p.values() do
          m(k) = v
        end
        m
      end
      _RouteMatch(f, ri, gs, frozen)
    else
      None
    end

  fun _lookup(path: String, offset: USize):
    ((HandlerFactory, (Array[ResponseInterceptor val] val | None),
      (Array[RequestInterceptor val] val | None),
      Array[(String, String)] val) | None)
  =>
    """
    Recursive lookup returning factory, response interceptors, request
    interceptors, and accumulated params.

    Params are built bottom-up: the leaf returns an empty val array, and each
    param level prepends its parameter to the child's val result.
    """
    let empty_params: Array[(String, String)] val =
      recover val Array[(String, String)] end

    if offset >= path.size() then
      match _factory
      | let f: HandlerFactory =>
        return (f, _response_interceptors, _interceptors, empty_params)
      end
      return None
    end

    // Try static children first (priority over param)
    try
      let c = path(offset)?
      for (key, child) in _children.values() do
        if key == c then
          if _Paths.starts_with(path, offset, child._prefix) then
            match child._lookup(path, offset + child._prefix.size())
            | (let f: HandlerFactory,
               let ri: (Array[ResponseInterceptor val] val | None),
               let gs: (Array[RequestInterceptor val] val | None),
               let p: Array[(String, String)] val) =>
              return (f, ri, gs, p)
            end
          end
          break
        end
      end
    else
      _Unreachable()
    end

    // Try parameter child
    match _param_child
    | let child: _TreeNode val =>
      let value_end = _Paths.find_char(path, '/', offset)
      if value_end > offset then
        let value = path.trim(offset, value_end)
        match child._lookup(path, value_end)
        | (let f: HandlerFactory,
           let ri: (Array[ResponseInterceptor val] val | None),
           let gs: (Array[RequestInterceptor val] val | None),
           let child_params: Array[(String, String)] val) =>
          let with_param: Array[(String, String)] val = recover val
            let a = Array[(String, String)]
            a.push((child._param_name, value))
            for (k, v) in child_params.values() do
              a.push((k, v))
            end
            a
          end
          return (f, ri, gs, with_param)
        end
      end
    end

    // Try wildcard
    match _wildcard_factory
    | let f: HandlerFactory =>
      let remainder = path.trim(offset)
      let wildcard_params: Array[(String, String)] val = recover val
        let a = Array[(String, String)]
        a.push((_wildcard_name, remainder))
        a
      end
      return (f, _wildcard_response_interceptors, _wildcard_interceptors,
        wildcard_params)
    end

    None

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
