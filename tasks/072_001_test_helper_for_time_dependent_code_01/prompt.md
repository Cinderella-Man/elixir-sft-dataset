# Specification: `Clock` Behaviour with Production and Test Implementations

## Overview

This specification describes an Elixir `Clock` behaviour together with two implementations of it — one intended for production use and one intended for testing — all delivered in a single file.

The behaviour defines exactly one callback: `now/0`, which returns the current time as a `DateTime`.

The purpose of the arrangement is to let application code accept a `:clock` dependency injection option and call `Clock.now(clock)` uniformly, without caring which implementation is underneath.

## API

### `Clock.Real` — the production implementation

`Clock.Real` implements `now/0` by delegating to `DateTime.utc_now()`.

### `Clock.Fake` — the test implementation

`Clock.Fake` is a `GenServer` exposing the following public API:

- `Clock.Fake.start_link(opts)` — starts the process. It accepts an optional `:initial` datetime, which defaults to `~U[2024-01-01 00:00:00Z]`, and an optional `:name` for registration.
- `Clock.Fake.now(server)` — returns the currently frozen datetime.
- `Clock.Fake.freeze(server, datetime)` — sets the clock to a specific `DateTime`, replacing whatever time was there. It may move the clock backwards as well as forwards.
- `Clock.Fake.advance(server, duration)` — moves the clock forward from its current value; repeated calls are cumulative. The `duration` argument is a keyword list such as `[seconds: 30]` or `[hours: 1, minutes: 30]`, applied via `DateTime.add/4`.

### `Clock` — the top-level dispatching module

In addition to the behaviour itself, a top-level `Clock` module provides a `now/1` function. It accepts either the `Clock.Real` module atom or a `Clock.Fake` PID / registered name, and dispatches correctly:

- when given `Clock.Real`, it calls `Clock.Real.now()`;
- when given a `Clock.Fake` PID or a registered-name atom (for example `:my_test_clock`), it calls `Clock.Fake.now(server)`.

## Edge cases

A registered name is itself an atom. Consequently, dispatch must distinguish a callable clock module from a registered-name atom rather than treating every atom as a module.

## Delivery constraints

The complete implementation is to be supplied in a single file with no external dependencies, using only the Elixir standard library and OTP.
