## Recover from idle timer subscription failures

Under sustained kernel resource pressure, the idle timer's ASIO event subscription could fail (for example, `ENOMEM` from `kevent` or `epoll_ctl`). When that happened, the timer was silently cancelled — idle connections stopped being reaped for the rest of that connection's lifetime, letting stale connections accumulate.

The idle timer now automatically re-arms after an ASIO subscription failure using the originally configured duration, so idle-timeout protection resumes on the next ASIO turn. If the re-armed subscription also fails, re-arm attempts continue until one succeeds.

## Require ponyc 0.64.0 or later

hobby now requires ponyc 0.64.0 or later. The previous minimum was 0.63.1.

This is driven by an update to stallion 0.7.0, which transitively requires ponyc 0.64.0 via lori 0.15.0 for changes to FFI declaration syntax and the runtime socket API. Older ponyc versions will fail to compile hobby.

