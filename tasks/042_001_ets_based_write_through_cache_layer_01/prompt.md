# `CacheLayer` — ETS-Backed Write-Through Cache Specification

## Overview

This document specifies an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed write-through cache.

The module runs as a GenServer that owns the lifecycle of all ETS tables it creates. Each `table` is an atom and corresponds to a separate ETS table owned by the GenServer. Tables are created lazily on first use — that is, the ETS table is created the first time a given table atom is seen.

The ETS tables are of type `:set` with public read access, so that `fetch` can read directly from ETS without going through the GenServer process, while writes and deletes are serialised through the GenServer.

The deliverable is the complete module in a single file, using only OTP and the standard library, with no external dependencies.

## API

The public API consists of the following functions.

### `CacheLayer.start_link(opts)`

Starts the process as a GenServer. It accepts a `:name` option for process registration, and it owns the lifecycle of all ETS tables it creates.

### `CacheLayer.fetch(server, table, key, fallback_fn)`

Returns the cached value for `{table, key}` if it exists in ETS. On a cache miss, it calls `fallback_fn.()`, stores the result in ETS, and returns it. The return value is always `{:ok, value}`.

Whatever `fallback_fn` returns is cached verbatim, so a stored `nil` (or any other falsy term) counts as a genuine cache hit and must **not** trigger a second fallback call on the next fetch.

### `CacheLayer.invalidate(server, table, key)`

Removes the entry for `{table, key}` from the cache. It returns `:ok` whether or not the entry existed.

### `CacheLayer.invalidate_all(server, table)`

Removes **all** cached entries for the given `table`. It returns `:ok` whether or not the table had any entries.

## Table discovery via `:persistent_term`

So that `fetch` can locate a table's ETS tid without a GenServer round-trip, the tid is published to `:persistent_term` under the key `{CacheLayer, server_pid, table}` (where `server_pid` is the GenServer's own pid) when the table is first created.

## Edge cases

- **Falsy cached values.** A cached `nil` — or any other falsy term returned by `fallback_fn` — is a genuine cache hit and must not cause a second fallback call on a subsequent fetch.
- **Invalidating absent entries.** Both `CacheLayer.invalidate(server, table, key)` and `CacheLayer.invalidate_all(server, table)` return `:ok` regardless of whether the entry, or any entry for the table, existed.
- **Shutdown cleanup.** When the GenServer stops, it must erase these `:persistent_term` entries — after `GenServer.stop/1`, `:persistent_term.get({CacheLayer, pid, table})` must no longer return a tid — and the ETS tables it owned must be freed.
- **At-most-once fallback.** The `fallback_fn` is a zero-arity anonymous function that the caller supplies. It will typically query a database. The implementation must guarantee it is called **at most once** per cache miss — it must not be called more than once even under concurrent access.
