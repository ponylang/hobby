## Fix 405 Allow header to include methods from all matching branches

The `Allow` header on 405 responses now reports all methods that would succeed for the URL, not just the methods from the highest-priority matching branch.

Previously, when a path matched multiple router branches at different priorities (e.g., a param route and a wildcard route), the `Allow` header only included methods from the first branch checked. For example, with `POST /files/:id` and `GET /files/*path` registered, a `DELETE /files/readme.txt` request returned `Allow: POST` — omitting `GET` and `HEAD` from the wildcard branch. The response now correctly returns `Allow: POST, GET, HEAD`.

This only affects paths that match multiple priority branches. Exact-path requests (where the URL has no remaining segments to match against wildcards) are unchanged.
