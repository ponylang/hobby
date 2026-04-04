class val BuiltApplication
  """
  An opaque proof token that routes have been validated and compiled.

  Created by `Application.build()` after route validation succeeds.
  Contains a frozen, immutable routing tree that can be shared across
  actors (`val` capability). Pass to `Server` or `Server.ssl` to start
  listening.

  There are no public methods — `BuiltApplication` exists solely to
  prove that route configuration is valid. The routing tree is accessed
  internally by `Server`.
  """

  let _router: _Router val

  new val _create(router: _Router val) =>
    _router = router

  fun val _get_router(): _Router val =>
    _router

type BuildResult is (BuiltApplication | ConfigError)
  """
  The result of `Application.build()`: either the routes compiled
  successfully (`BuiltApplication`) or a configuration error was
  detected (`ConfigError`).
  """
