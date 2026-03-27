## Fix param and wildcard routes failing when a static route shares a long prefix

Routes with `:param` or `*wildcard` segments returned 404 when another static route on the same HTTP method shared a common prefix and was registered first. For example, registering `POST /a/b/c/login` followed by `POST /a/b/c/user/:id/filter` caused the second route to never match.

The router's radix tree splits nodes when routes diverge mid-prefix. The split path was storing the remaining suffix as literal text instead of parsing `:` and `*` markers, so param and wildcard segments after the split point were silently ignored. Route registration order should never affect whether a route matches, and now it doesn't.
