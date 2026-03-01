primitive _JoinPath
  """
  Join a group prefix with a route path.

  Strips any trailing slash from the prefix, then concatenates with
  the route path (which always starts with `/`). If the prefix is
  empty, returns the route path unchanged.

  Examples: `("/api/", "/users")` -> `"/api/users"`,
  `("/", "/health")` -> `"/health"`,
  `("", "/health")` -> `"/health"`.
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
      if
        (s.size() > 0)
          and (s(s.size() - 1)? == '/')
      then
        return s.trim(0, s.size() - 1)
      end
    else
      _Unreachable()
    end
    s

primitive _ConcatMiddleware
  """
  Concatenate two optional middleware arrays.

  Returns a combined array with outer middleware first, then inner
  middleware. When one side is `None`, returns the other directly
  (no allocation). When both are `None`, returns `None`.
  """
  fun apply(
    outer: (Array[Middleware val] val | None),
    inner: (Array[Middleware val] val | None))
    : (Array[Middleware val] val | None)
  =>
    match (outer, inner)
    | (let o: Array[Middleware val] val,
      let i: Array[Middleware val] val)
    =>
      recover val
        let combined =
          Array[Middleware val](
            o.size() + i.size())
        for mw in o.values() do
          combined.push(mw)
        end
        for mw in i.values() do
          combined.push(mw)
        end
        combined
      end
    | (let o: Array[Middleware val] val, None) =>
      o
    | (None, let i: Array[Middleware val] val) =>
      i
    else
      None
    end
