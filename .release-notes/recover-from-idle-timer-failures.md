## Recover from idle timer subscription failures

Under sustained kernel resource pressure, the idle timer's ASIO event subscription could fail (for example, `ENOMEM` from `kevent` or `epoll_ctl`). When that happened, the timer was silently cancelled — idle connections stopped being reaped for the rest of that connection's lifetime, letting stale connections accumulate.

The idle timer now automatically re-arms after an ASIO subscription failure using the originally configured duration, so idle-timeout protection resumes on the next ASIO turn. If the re-armed subscription also fails, re-arm attempts continue until one succeeds.
