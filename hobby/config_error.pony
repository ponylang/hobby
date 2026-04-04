class val ConfigError
  """
  Returned by `Application.build()` when a configuration error
  prevented the routes from compiling.

  Contains a human-readable description of the error. Common causes:
  - Overlapping group prefixes (two groups with the same prefix)
  - Empty group prefix (use `add_request_interceptor()` instead)
  - Special characters in group prefix (`:` or `*`)
  - Conflicting param names at the same path position across methods
  - Conflicting wildcard names at the same path position across methods
  - Segments after a wildcard (wildcards capture the entire remainder)
  - Empty param name (bare `:` with no name)
  - Empty wildcard name (bare `*` with no name)
  """
  let message: String

  new val create(message': String) =>
    message = message'
