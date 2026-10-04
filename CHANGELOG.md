# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.0] - 2026-10-04

### Added

- `zcli_help` declaration for command-level help descriptions.
- Built-in `--help` / `-h` handling via `error.HelpRequested`.
- Combined boolean short flags (e.g. `-vf` sets both `-v` and `-f`).
- Inline assignment for short flags (`-n=script.sh`).
- Parent/global flags placed before subcommands (`myapp --verbose run -n file`).
- Slice flags via `.kind = .flag` for `[]const []const u8` fields (`--include a --include b`).
- Duplicate flag detection (`error.DuplicateFlag`).

### Changed

- Verified compatibility with the stable Zig 0.17.0 release.

## [0.2.0] - 2026-06-14

### Added

- `zcli_options` declaration for per-field help text and single-character shortcuts.
- Shortcut parsing in the argument parser (`-v` maps to `--verbose`).
- Help renderer displays shortcuts when configured.

## [0.1.0] - 2026-06-14

### Added

- Comptime-driven CLI definition via plain Zig structs.
- Type-safe flag parsing for `bool`, integers, floats, `[]const u8`, `enum`, and optional variants.
- Positional argument support: required, optional, and variadic.
- Nested struct subcommands with compile-time dispatch.
- Pure parser that returns narrow errors instead of calling `std.process.exit`.
- Help, usage, and diagnostic rendering.
- Comprehensive test suite using `std.testing.allocator`.
- Working demo CLI under `examples/demo/`.
- Open source documentation: README, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT.
