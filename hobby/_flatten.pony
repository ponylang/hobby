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
  """Strip trailing slash from a string (unconditionally)."""
  fun apply(s: String): String =>
    try
      if (s.size() > 0) and (s(s.size() - 1)? == '/') then
        return s.trim(0, s.size() - 1)
      end
    else
      _Unreachable()
    end
    s

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
    | (let o: Array[ResponseInterceptor val] val,
       let i: Array[ResponseInterceptor val] val) =>
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
    | (let o: Array[RequestInterceptor val] val,
       let i: Array[RequestInterceptor val] val) =>
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
