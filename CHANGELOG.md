# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

### Fixed


### Added


### Changed


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

