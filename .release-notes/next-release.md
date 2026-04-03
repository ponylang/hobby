## Reject segments after wildcard in route registration

Registering a route with segments after a wildcard (e.g., `/files/*path/extra`) previously dropped the trailing segments silently — the route would behave as if only `/files/*path` had been registered. This now produces a `ConfigError` at startup, so you'll see the misconfiguration immediately instead of getting surprising routing behavior at runtime.

