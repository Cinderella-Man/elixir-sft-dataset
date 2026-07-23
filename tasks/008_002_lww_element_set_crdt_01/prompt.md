# LWWSet — Last-Writer-Wins Element Set Specification

## Overview

This document specifies an Elixir GenServer module named `LWWSet` that maintains a Last-Writer-Wins Element Set (LWW-Element-Set) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

The module's internal state tracks, for each element, the latest add timestamp and the latest remove timestamp as two separate maps. For example, after `add(s, :x, 10)` and `remove(s, :x, 5)`, the element `:x` is still in the set because `10 > 5`. After `remove(s, :x, 15)`, it would no longer be in the set because `15 > 10`.

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.

The complete module must be delivered in a single file. It must use only the OTP standard library, with no external dependencies.

## API

The public API consists of the following functions:

- `LWWSet.start_link(opts)` starts the process. It accepts a `:name` option for process registration. It returns `{:ok, pid}`.

- `LWWSet.add(server, element, timestamp)` adds an element to the set with the given timestamp. If the element was already added with an earlier timestamp, the timestamp is updated to the newer one. It returns `:ok`.

- `LWWSet.remove(server, element, timestamp)` marks an element as removed at the given timestamp. It returns `:ok`.

- `LWWSet.member?(server, element)` returns `true` if the element is currently in the set, `false` otherwise. An element is considered present if its add timestamp is strictly greater than its remove timestamp (or if it has been added but never removed).

- `LWWSet.members(server)` returns a `MapSet` of all elements currently in the set (i.e., all elements whose add timestamp is strictly greater than their remove timestamp, or who have been added but never removed).

- `LWWSet.merge(server, remote_state)` merges a remote set state into the local one. `remote_state` has the same shape returned by `LWWSet.state/1` (a map with `:adds` and `:removes` keys), and either map may omit elements. For each element, the merged result takes the maximum of the local and remote add timestamps, and separately the maximum of the local and remote remove timestamps. This is the standard LWW-Element-Set merge rule. It returns `:ok`.

- `LWWSet.state(server)` returns the raw internal state of the set so it can be sent to another node for merging. It is returned as a map with two keys: `:adds` for the add map (element => timestamp) and `:removes` for the remove map (element => timestamp). An element appears in a given map only if the corresponding operation was applied to it, so looking up an element that was never added returns `nil` in `:adds`, and one that was never removed returns `nil` in `:removes`. The state of a fresh set is `%{adds: %{}, removes: %{}}`.

## Edge cases

- Timestamps must be positive integers. If someone tries to pass a non-positive timestamp, the function must raise an `ArgumentError`.

- When add and remove have the exact same timestamp for an element, the element must be considered **not** in the set (remove-wins bias on ties).
