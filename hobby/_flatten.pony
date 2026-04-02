primitive _SplitSegments
  """

  Split a normalized path into an array of path segments.

  Strips the leading slash and splits on `/`, skipping empty segments
  (which normalizes double slashes). `/api/users/:id` → `["api", "users",
  ":id"]`. `/` → `[]`. `/api//users` → `["api", "users"]`.
  """

  fun apply(path: String): Array[String] val =>
    if path.size() <= 1 then
      return recover val Array[String] end
    end
    recover val
      let segments = Array[String]
      var start: USize = 1  // skip leading '/'
      try
        while start < path.size() do
          // Find next '/'
          var end_pos = start
          while (end_pos < path.size()) and (path(end_pos)? != '/') do
            end_pos = end_pos + 1
          end
          if end_pos > start then
            segments.push(path.trim(start, end_pos))
          end
          start = end_pos + 1
        end
      else
        _Unreachable()
      end
      segments
    end

primitive _JoinRemainingSegments
  """

  Join segments from a start index onward with `/` separators.

  Used to reconstruct the captured value for wildcard parameters.
  """

  fun apply(
    segments: Array[String] val,
    from: USize,
    size_hint: USize = 0)
    : String
  =>
    if from >= segments.size() then
      return ""
    end
    try
      if (from + 1) == segments.size() then
        return segments(from)?
      end
    else
      _Unreachable()
    end
    recover val
      let s = String(size_hint)
      var i = from
      try
        while i < segments.size() do
          if i > from then s.push('/') end
          s.append(segments(i)?)
          i = i + 1
        end
      else
        _Unreachable()
      end
      s
    end

primitive _JoinPath
  """

  Join a group prefix with a route path.

  Strips any trailing slash from the prefix, then concatenates with the route
  path (which always starts with `/`). If the prefix is empty, returns the
  route path unchanged.

  Examples: `("/api/", "/users")` -> `"/api/users"`,
  `("/", "/health")` -> `"/health"`, `("", "/health")` -> `"/health"`.
  """

  fun apply(prefix: String, path: String): String =>
    if prefix.size() == 0 then
      return path
    end
    let trimmed = _TrimTrailingSlash(prefix)
    if trimmed.size() == 0 then
      // Prefix was just "/", return path as-is
      path
    else
      trimmed + path
    end

primitive _TrimTrailingSlash
  """
  Strip trailing slash from a string (unconditionally).
  """
  fun apply(s: String): String =>
    try
      if (s.size() > 0) and (s(s.size() - 1)? == '/') then
        return s.trim(0, s.size() - 1)
      end
    else
      _Unreachable()
    end
    s

primitive _ValidateGroups
  """

  Validate group configuration before tree insertion.

  Called in `Application.serve()` where the original full prefix strings
  are available. Returns the first error found, or `None` if all groups
  are valid. Checks:
  - Empty prefix (collides with app-level interceptors)
  - Special characters in prefix (`:` or `*`)
  - Overlapping prefixes (two groups with the same prefix)
  """

  fun apply(infos: Array[_GroupInfo] box): (ConfigError | None) =>
    for gi in infos.values() do
      if (gi.prefix.size() == 0) or (gi.prefix == "/") then
        return ConfigError(
          "RouteGroup with prefix \"" + gi.prefix +
          "\" is equivalent to app-level interceptors. " +
          "Use add_request_interceptor() / " +
          "add_response_interceptor() instead.")
      end
      if _HasSpecialChars(gi.prefix) then
        return ConfigError(
          "RouteGroup prefix '" + gi.prefix +
          "' contains ':' or '*'. Group prefixes must be static paths " +
          "— use route-level params instead.")
      end
    end
    var i: USize = 0
    while i < infos.size() do
      var j = i + 1
      while j < infos.size() do
        try
          if infos(i)?.prefix == infos(j)?.prefix then
            return ConfigError(
              "Overlapping group interceptors on prefix '" +
              infos(i)?.prefix +
              "'. Two groups cannot register interceptors on the same " +
              "prefix.")
          end
        else
          _Unreachable()
        end
        j = j + 1
      end
      i = i + 1
    end
    None

primitive _HasSpecialChars
  """
  Check if a string contains `:` or `*` (param/wildcard markers).
  """
  fun apply(s: String box): Bool =>
    var i: USize = 0
    try
      while i < s.size() do
        let c = s(i)?
        if (c == ':') or (c == '*') then return true end
        i = i + 1
      end
    else
      _Unreachable()
    end
    false

primitive _ConcatResponseInterceptors
  """

  Concatenate two optional response interceptor arrays.

  Returns a combined array with outer interceptors first, then inner.
  When one side is `None`, returns the other directly (no allocation).
  When both are `None`, returns `None`.
  """

  fun apply(
    outer: (Array[ResponseInterceptor val] val | None),
    inner: (Array[ResponseInterceptor val] val | None))
    : (Array[ResponseInterceptor val] val | None)
  =>
    match (outer, inner)
    | ( let o: Array[ResponseInterceptor val] val,
        let i: Array[ResponseInterceptor val] val
      ) =>
      recover val
        let combined =
          Array[ResponseInterceptor val](o.size() + i.size())
        for ri in o.values() do
          combined.push(ri)
        end
        for ri in i.values() do
          combined.push(ri)
        end
        combined
      end
    | (let o: Array[ResponseInterceptor val] val, None) => o
    | (None, let i: Array[ResponseInterceptor val] val) => i
    else
      None
    end

primitive _ConcatInterceptors
  """

  Concatenate two optional interceptor arrays.

  Returns a combined array with outer interceptors first, then inner.
  When one side is `None`, returns the other directly (no allocation).
  When both are `None`, returns `None`.
  """

  fun apply(
    outer: (Array[RequestInterceptor val] val | None),
    inner: (Array[RequestInterceptor val] val | None))
    : (Array[RequestInterceptor val] val | None)
  =>
    match (outer, inner)
    | ( let o: Array[RequestInterceptor val] val,
        let i: Array[RequestInterceptor val] val
      ) =>
      recover val
        let combined =
          Array[RequestInterceptor val](o.size() + i.size())
        for g in o.values() do
          combined.push(g)
        end
        for g in i.values() do
          combined.push(g)
        end
        combined
      end
    | (let o: Array[RequestInterceptor val] val, None) => o
    | (None, let i: Array[RequestInterceptor val] val) => i
    else
      None
    end
