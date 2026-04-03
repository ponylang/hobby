## Reject segments after wildcard in route registration

Registering a route with segments after a wildcard (e.g., `/files/*path/extra`) previously dropped the trailing segments silently — the route would behave as if only `/files/*path` had been registered. This now produces a `ConfigError` at startup, so you'll see the misconfiguration immediately instead of getting surprising routing behavior at runtime.

## Reject empty param and wildcard names in route registration

Registering a route with a bare `:` or `*` (no name after the prefix character, e.g., `/users/:` or `/files/*`) previously accepted the route silently with an empty name. This caused the conflict detection to miss cases where a later route registered a named param or wildcard at the same position. Both bare `:` and bare `*` now produce a `ConfigError` at startup.

