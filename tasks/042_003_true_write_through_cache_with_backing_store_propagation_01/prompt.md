# `CacheLayer` — True Write-Through Cache with Backing-Store Propagation

## Overview

`CacheLayer` is a single Elixir module implementing a **true write-through cache**. Reads are served from an ETS cache with read-through fill. Writes and deletes are propagated to a backing store *before* the cache is updated, so the cache is never ahead of the store.

The deliverable is the complete module in a single file, built on OTP and the standard library only, with no external dependencies.

## API

The module exposes the following public functions.

### `CacheLayer.start_link(opts)`

Starts the process as a GenServer. It accepts a `:name` option for process registration and owns the lifecycle of all ETS tables it creates.

### `CacheLayer.fetch(server, table, key, loader_fn)`

Read-through. If `{table, key}` is cached, the function returns `{:ok, value}`, read directly from ETS. On a miss it calls `loader_fn.()` — a zero-arity function that loads from the store and returns the value — **at most once**, caches the result, and returns `{:ok, value}`.

### `CacheLayer.put(server, table, key, value, writer_fn)`

Write-through. `writer_fn` is a zero-arity function that persists the value to the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. `writer_fn.()` is called first; **only if it succeeds** is the cache updated to `value` and `{:ok, value}` returned. If it returns `{:error, reason}`, the cache is left untouched and `{:error, reason}` is returned.

### `CacheLayer.delete(server, table, key, deleter_fn)`

Delete-through. `deleter_fn` is a zero-arity function that removes the key from the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. It is called first; **only if it succeeds** is the entry removed from the cache and `:ok` returned. On `{:error, reason}`, the cache is left untouched and `{:error, reason}` is returned.

### `CacheLayer.invalidate(server, table, key)`

Cache-only eviction. Removes the cached entry **without touching the backing store**. Returns `:ok`.

### `CacheLayer.invalidate_all(server, table)`

Cache-only eviction of **all** entries for the table, leaving the store untouched. Returns `:ok`.

## Storage and concurrency model

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. Cached reads must be servable directly from ETS without a GenServer round-trip. All loads, writes, and deletes are serialised through the GenServer so that the store functions and the cache never race.

## Edge cases and consistency guarantees

- The key consistency rule: the cache is only mutated on a *successful* store operation — a failed `put`/`delete` must leave the previously cached value exactly as it was.
- `loader_fn.()` must be invoked at most once per cache miss.
- Because cached reads bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call.
- If anything process-global is registered for that lookup (for example `:persistent_term` entries), the server must trap exits, and its `terminate/2` must erase every such registration when it stops — including a supervised shutdown — so that a cleanly stopped server leaves nothing behind. The ETS tables themselves die with their owner.
