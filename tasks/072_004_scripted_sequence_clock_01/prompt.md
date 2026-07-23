# Specification: Scripted `Clock` Behaviour with Real and Fake Implementations

## Overview

This document specifies an Elixir `Clock` behaviour together with two implementations — one intended for production use and one intended for testing — all delivered in a single file. The distinguishing property of this variation is that the fake clock is **scripted**: rather than holding a single frozen value, it hands back a predetermined sequence of timestamps, one per read. This makes it well suited to testing code that reads the clock several times.

The behaviour defines a single callback: `now/0`, which returns the current time as a `DateTime`.

The deliverable is the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.

## API

### Production implementation — `Clock.Real`

`Clock.Real` implements `now/0` by delegating to `DateTime.utc_now()`.

### Test implementation — `Clock.Fake`

`Clock.Fake` is a `GenServer` exposing the following public API.

#### `Clock.Fake.start_link(opts)`

Starts the process. It accepts the following options:

- `:script` — a non-empty list of `DateTime`s to hand out, one per `now/1` call. It defaults to `[~U[2024-01-01 00:00:00Z]]`.
- `:on_exhaust` — the policy applied once the script is consumed. It is one of:
  - `:repeat_last` — the default; the clock keeps returning the final value.
  - `:cycle` — the clock wraps around to the start.
  - `:raise` — every further `now/1` call raises a `RuntimeError` **in the process calling `now/1`**. `:raise` is implemented by having the server reply that the script is exhausted and letting the `now/1` client function raise; a raise inside the GenServer callback would crash the clock and turn the caller's call into an exit rather than a catchable raise.
- `:name` — an optional registration name.

#### `Clock.Fake.now(server)`

Returns the next scripted `DateTime`, advancing the internal cursor. Behaviour after the script is exhausted follows `:on_exhaust`.

#### `Clock.Fake.remaining(server)`

Returns how many scripted values have not yet been consumed. The result is never negative, and it is `0` once exhausted.

#### `Clock.Fake.reset(server)`

Rewinds the cursor to the beginning of the script.

#### `Clock.Fake.push(server, datetimes)`

Appends more `DateTime`s to the end of the script.

### Top-level dispatcher — `Clock.now/1`

In addition to the above, a top-level `Clock` module provides a `now/1` function that accepts either a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name, and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

## Edge cases

Starting must fail (`start_link` returns an `{:error, reason}` tuple) when validation fails:

- an empty script returns `{:error, :empty_script}`;
- a script containing a non-`DateTime` element returns `{:error, :invalid_script}`;
- an unknown `:on_exhaust` policy returns `{:error, :invalid_policy}`.
