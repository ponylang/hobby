## Fix crash when dispose() arrives before connection initialization

Fixed a crash that could occur when a connection was closed before its internal initialization completed. This timing-dependent issue was rare but was observed on macOS arm64.
