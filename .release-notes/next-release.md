## Reject malformed and smuggling-prone HTTP requests

Hobby's HTTP request handling previously accepted a range of malformed requests, including several recognized request-smuggling vectors. When your server sits behind or in front of another HTTP processor — a proxy, load balancer, or CDN — that disagrees about where one request ends and the next begins, an attacker could use these to slip a hidden request past one of them. Such requests are now rejected and the connection is closed.

A request is now rejected when, among other things, it carries both a `Content-Length` and a `Transfer-Encoding`, uses a bare CR or LF where a CRLF is required, contains a NUL byte or an invalid token in a header field, or uses an obsolete line-folded header — and trailer fields are held to the same standard as header fields. A `Transfer-Encoding` whose codings cannot frame the message — empty, or `chunked` not given as the single final coding — is now answered with `400 Bad Request`, while one naming a coding hobby does not implement is answered with `501 Not Implemented`; previously a loose substring check could match such a value and leave the request hanging with no response, where the connection is now closed instead. A well-formed method that hobby does not implement is likewise answered with `501 Not Implemented` rather than `400 Bad Request`.

Host validation is stricter as well. A request must carry exactly one `Host` header whose value is a well-formed host — a host name, IPv4 address, or bracketed IP-literal, with an optional port in range. A `Host` that disagrees with an authority named in the request-target, such as an absolute-form target or a CONNECT target, is rejected, as is a CONNECT target missing its port or any request-target carrying userinfo. These close request-routing ambiguities that could otherwise be exploited for smuggling.

## Accept valid quoted parameters in Transfer-Encoding and Accept headers

Hobby previously split `Transfer-Encoding` and `Accept` header values on their delimiters without respecting quoted strings, so a `,` or `;` inside a quoted parameter value tore a legal value in half. A valid request such as `Transfer-Encoding: chunked;ext="a,b"` was wrongly rejected as a bad request, and content negotiation could misread an `Accept` value carrying quoted parameters.

Hobby now respects double-quoted parameter values — including RFC 9110 backslash escapes — when parsing these headers, so such requests are handled correctly. A `Transfer-Encoding` whose quoted string is left unterminated is still rejected, since malformed framing metadata should be refused rather than framed on a guess.

## Honor a Connection: close request in all its valid forms

Hobby previously recognized a `Connection: close` directive only when `close` was the sole value on a single `Connection` header line. A `close` token sent alongside other options — `Connection: close, x-fake` or `Connection: keep-alive, close` — or on a second `Connection` line was ignored, so the connection stayed open instead of closing after the response. Browsers and proxies routinely send multi-token `Connection` values, so this affected ordinary traffic, not just unusual requests.

Hobby now reads `Connection` as the comma-separated list it is and honors a `close` token wherever it appears — anywhere in the list, in any case, and across repeated `Connection` header lines. A `close` token always takes precedence over `keep-alive`.

## Combine repeated lines of a comma-separated header when reading it

When a client sent a comma-separated list header — such as `Accept`, `Connection`, or `Cache-Control` — across more than one header line, reading it with `request.headers.get(...)` previously returned only the first line's value and silently dropped the rest, so a handler or interceptor inspecting that header saw an incomplete value.

Hobby now combines the repeated lines of a comma-separated list header into a single value, joined by commas in the order the lines arrived. Headers that are not comma-separated lists, such as `Set-Cookie`, are unaffected and still return their first value.
