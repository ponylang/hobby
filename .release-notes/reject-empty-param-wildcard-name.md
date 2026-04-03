## Reject empty param and wildcard names in route registration

Registering a route with a bare `:` or `*` (no name after the prefix character, e.g., `/users/:` or `/files/*`) previously accepted the route silently with an empty name. This caused the conflict detection to miss cases where a later route registered a named param or wildcard at the same position. Both bare `:` and bare `*` now produce a `ConfigError` at startup.
