# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [0.9.0] - 2026-06-30

### Fixed

- Fix idle timeout never closing stalled connections ([PR #107](https://github.com/ponylang/hobby/pull/107))
- Fix connections closed mid-transfer by the idle timeout ([PR #107](https://github.com/ponylang/hobby/pull/107))

### Changed

- Drop support for Windows 10 ([PR #107](https://github.com/ponylang/hobby/pull/107))

## [0.8.3] - 2026-06-22

### Fixed

- Fix server going silent after sending a large response ([PR #106](https://github.com/ponylang/hobby/pull/106))

## [0.8.2] - 2026-06-10

### Fixed

- Fix truncated streaming responses to slow clients ([PR #105](https://github.com/ponylang/hobby/pull/105))

## [0.8.1] - 2026-06-08

### Fixed

- Reject malformed and smuggling-prone HTTP requests ([PR #104](https://github.com/ponylang/hobby/pull/104))
- Accept valid quoted parameters in Transfer-Encoding and Accept headers ([PR #104](https://github.com/ponylang/hobby/pull/104))
- Honor a Connection: close request in all its valid forms ([PR #104](https://github.com/ponylang/hobby/pull/104))
- Combine repeated lines of a comma-separated header when reading it ([PR #104](https://github.com/ponylang/hobby/pull/104))

## [0.8.0] - 2026-05-28

### Fixed

- Recover from idle timer subscription failures ([PR #93](https://github.com/ponylang/hobby/pull/93))

### Changed

- Require ponyc 0.64.0 or later ([PR #101](https://github.com/ponylang/hobby/pull/101))

## [0.7.0] - 2026-04-12

### Fixed

- Fix potential connection hang when timer event subscription fails ([PR #92](https://github.com/ponylang/hobby/pull/92))

### Changed

- Require ponyc 0.63.1 or later ([PR #92](https://github.com/ponylang/hobby/pull/92))

## [0.6.1] - 2026-04-07

### Fixed

- Fix connection stall after large response with backpressure ([PR #85](https://github.com/ponylang/hobby/pull/85))

## [0.6.0] - 2026-04-04

### Fixed

- Reject segments after wildcard in route registration ([PR #77](https://github.com/ponylang/hobby/pull/77))
- Reject empty param and wildcard names in route registration ([PR #78](https://github.com/ponylang/hobby/pull/78))

### Changed

- Separate route compilation from server startup ([PR #80](https://github.com/ponylang/hobby/pull/80))

## [0.5.0] - 2026-04-03

### Fixed

- Fix 405 Allow header to include methods from all matching branches ([PR #68](https://github.com/ponylang/hobby/pull/68))

### Added

- Add request interceptors for synchronous request short-circuiting ([PR #55](https://github.com/ponylang/hobby/pull/55))
- Add response interceptors for synchronous response modification ([PR #57](https://github.com/ponylang/hobby/pull/57))
- Add HTTPS support via serve_ssl() ([PR #75](https://github.com/ponylang/hobby/pull/75))

### Changed

- Remove middleware in favor of interceptors ([PR #57](https://github.com/ponylang/hobby/pull/57))
- Interceptors now run on 404 responses under their path ([PR #59](https://github.com/ponylang/hobby/pull/59))

## [0.4.1] - 2026-03-28

### Fixed

- Fix param and wildcard routes failing when a static route shares a long prefix ([PR #53](https://github.com/ponylang/hobby/pull/53))
- Fix crash when dispose() arrives before connection initialization ([PR #54](https://github.com/ponylang/hobby/pull/54))

### Added

- Add signed cookie support ([PR #47](https://github.com/ponylang/hobby/pull/47))

## [0.4.0] - 2026-03-22

### Fixed

- Fix premature idle timeouts on SSL connections ([PR #43](https://github.com/ponylang/hobby/pull/43))

### Changed

- Redesign handler model to actor-per-request ([PR #42](https://github.com/ponylang/hobby/pull/42))

## [0.3.0] - 2026-03-16

### Added

- Add cookie support ([PR #39](https://github.com/ponylang/hobby/pull/39))
- Add content negotiation ([PR #39](https://github.com/ponylang/hobby/pull/39))

### Changed

- Change `Headers.values()` to yield `Header val` ([PR #39](https://github.com/ponylang/hobby/pull/39))

## [0.2.1] - 2026-03-13

### Added

- Add built-in static file serving handler ([PR #19](https://github.com/ponylang/hobby/pull/19))
- Add caching headers for ServeFiles ([PR #23](https://github.com/ponylang/hobby/pull/23))
- Add automatic index file serving for directories ([PR #24](https://github.com/ponylang/hobby/pull/24))

## [0.2.0] - 2026-02-23

### Fixed

- Buffer pipelined requests during streaming responses ([PR #15](https://github.com/ponylang/hobby/pull/15))

### Added

- Add streaming response support ([PR #14](https://github.com/ponylang/hobby/pull/14))

### Changed

- Return typed result from start_streaming() ([PR #16](https://github.com/ponylang/hobby/pull/16))

## [0.1.0] - 2026-02-22

### Added

- Initial version

