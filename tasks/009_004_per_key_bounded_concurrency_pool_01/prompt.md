# KeyedPool — Per-Key Bounded Concurrency Pool Specification

## Overview

This document specifies an Elixir GenServer module named `KeyedPool` that limits the number of concurrent executions per key, acting as a per-key bounded concurrency pool. The complete module is to be delivered in a single file, using only the OTP standard library with no external dependencies.

Different keys are completely independent — each key has its own concurrency count and queue.

## API

The public API comprises the following functions.

### `KeyedPool.start_link(opts)`

Starts the process. It accepts a `:name` option for process registration and a required `:max_concurrency` option (the maximum number of simultaneous executions allowed per key, which must be a positive integer). If the `:max_concurrency` option is missing, it raises a `KeyError`. If it is present but is not a positive integer (for example `0`, `-1`, or `1.5`), it raises an `ArgumentError`.

### `KeyedPool.execute(server, key, func)`

Here `func` is a zero-arity function. If the number of currently running executions for `key` is below `:max_concurrency`, the function is executed immediately in a spawned Task (so the GenServer remains responsive) and the caller blocks until the result is ready. If `:max_concurrency` executions are already running for that key, the caller is placed in a FIFO queue and blocks until a slot opens. When a running execution completes, the next queued caller's function is started.

Each caller gets the result of **their own** function — this is NOT request deduplication. Every caller's function runs independently.

Return value normalisation applies as follows: if `func` returns `{:ok, value}`, the caller gets `{:ok, value}`. If `func` returns `{:error, reason}`, the caller gets `{:error, reason}`. If `func` returns any other term `v`, the caller gets `{:ok, v}`. If `func` raises, the caller gets `{:error, {:exception, exception}}`, where `exception` is the raised exception struct (e.g. `{:error, {:exception, %RuntimeError{message: "boom"}}}`).

### `KeyedPool.status(server, key)`

Returns a map `%{running: non_neg_integer(), queued: non_neg_integer()}` showing how many executions are running and how many callers are waiting in the queue for the given key. It returns `%{running: 0, queued: 0}` for keys with no activity.

## Edge cases

When a slot frees up (a running execution finishes) and there are queued callers, the GenServer must automatically start the next queued caller's function. The queue is strictly FIFO.

If a Task crashes (func raises), it must still free its slot and the queued caller's function should be started next. The crashing caller gets `{:error, {:exception, exception}}`.
