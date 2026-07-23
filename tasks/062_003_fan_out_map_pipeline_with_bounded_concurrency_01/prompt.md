# Specification — `Pipeline`: Composable Linear Pipelines with Fan-Out Map Stages

## Overview

This document specifies an Elixir module called `Pipeline` that builds and runs linear processing pipelines from composable stages, with support for **fan-out map stages** that process a collection concurrently.

The implementation must use only the standard library, with no external dependencies. The complete implementation is to be delivered in a single file.

## API

The public API consists of the following functions.

### `Pipeline.new()`

Returns a fresh, empty pipeline struct.

### `Pipeline.stage(pipeline, name, fun)`

Appends a normal **sequential** stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`.

### `Pipeline.map_stage(pipeline, name, fun, opts \\ [])`

Appends a **fan-out** stage. Its input must be a list. `fun` is a one-arity function applied to **each element** concurrently, returning `{:ok, element_result}` or `{:error, reason}`. `opts` may contain `:max_concurrency` (a positive integer); when omitted, there is no concurrency bound — **every** element runs concurrently at once.

Element results must be collected in **input order**. If every element succeeds, the stage's output is the list of element results (threaded to the next stage). If any element fails, the stage fails with the **first** failure by input index, and the `reason` is that element's `{:error, reason}` reason.

### `Pipeline.run(pipeline, input)`

Executes all stages in insertion order, threading each stage's output into the next.

On full success it returns `{:ok, final_result, metadata}`, where `metadata` is a list of entries in execution order:

- sequential stage: `%{stage: atom, duration_us: non_neg_integer, type: :sequential, count: 1}`
- map stage: `%{stage: atom, duration_us: non_neg_integer, type: :map, count: non_neg_integer}` where `count` is the number of input elements.

On the first failing stage, execution halts immediately and the call returns `{:error, failed_stage_name, reason}` — no later stages are run.

## Implementation constraints

- Fan-out concurrency must use `Task.async_stream/3` (or equivalent) with ordered results and the requested `:max_concurrency`.
- Timing per stage must be measured with `:timer.tc/1` (microsecond resolution).

## Edge cases

- An empty pipeline returns the input unchanged with empty metadata.
- If a map stage receives a non-list input, it raises `ArgumentError`.
- When a map stage has multiple failing elements, the failure reported is the **first** one by input index.
- When `:max_concurrency` is omitted from `opts`, the map stage imposes no concurrency bound and every element runs concurrently at once.
