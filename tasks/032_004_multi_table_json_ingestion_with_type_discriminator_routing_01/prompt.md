# MultiSchemaIngestion — Specification

## Overview

This document specifies an Elixir module named `MultiSchemaIngestion`. The module reads a JSON array file in which each record carries a `"type"` discriminator field, routes each record to the appropriate Ecto schema according to a caller-supplied routing map, and batch-inserts each resulting group into its respective database table.

The complete module is to be delivered in a single file. Jason and Ecto may be assumed available as dependencies; nothing else is to be added.

For I/O and parsing the module uses `File.read/1` + `Jason.decode/1`. For batching it uses `Enum.chunk_every/2`. It uses `require Logger` and emits a `Logger.info/1` line after every batch giving the schema name and the running totals — including after failed batches; the error log does not replace it.

## API

The public API consists of the following functions:

- `MultiSchemaIngestion.ingest(repo, routing, file_path, opts \\ [])` — the main entry point. `routing` is a map from type-discriminator strings to Ecto schema modules, e.g. `%{"order" => MyApp.Order, "refund" => MyApp.Refund}`.

  This function reads the JSON file at `file_path`, decodes the top-level array, groups records by their `"type"` field, and for each group inserts rows in batches via `repo.insert_all/3`. It returns `{:ok, stats}` on success or `{:error, reason}` on failure.

  `stats` is a map with these keys:
    - `:total`          — total records read from the file (integer)
    - `:by_schema`      — a map from schema module to per-schema stats: `%{inserted: integer(), failed: integer()}`
    - `:unroutable`     — count of records whose `"type"` value did not match any key in the routing map (integer)
    - `:missing_type`   — count of records that had no `"type"` field at all (integer)

### Accepted `opts`

- `:batch_size` (integer, default 500) — how many records per `insert_all` call, applied independently per schema group
- `:on_conflict` (atom or keyword, default `:nothing`) — passed to `Repo.insert_all` as `on_conflict:`
- `:conflict_target` (atom, list, or a map from schema module to atom/list, default `:nothing`) — when a plain atom or list, the same target is used for all schemas. When a map, each schema can have its own conflict target, e.g. `%{MyApp.Order => [:order_id], MyApp.Refund => [:refund_id]}`
- `:type_field` (string, default `"type"`) — the JSON key used as the type discriminator

### Processing order

Records for each schema group are inserted in the order they appeared in the original file. Groups are processed in the order of their first appearance.

### Record transformation

Before insertion, the module converts string-keyed JSON maps to atom-keyed maps using only fields declared on each target schema (via `schema.__schema__(:fields)`), drops the discriminator field, and injects `inserted_at` / `updated_at` timestamps if the schema declares them.

### Additional interface contract

- `:by_schema` contains an entry for EVERY schema module in the routing map, including schemas that received no records — those map to `%{inserted: 0, failed: 0}` (so even an empty input array yields all schemas with zero counts).

## Edge cases

The module must handle these error conditions gracefully — it must never raise:

- File not found → `{:error, :file_not_found}`
- File is not valid JSON → `{:error, :invalid_json}`
- File contains valid JSON but not a top-level array → `{:error, :not_a_list}`
- A record has no `"type"` field → count as `:missing_type`, skip it
- A record's `"type"` value is not in the routing map → count as `:unroutable`, skip it. The discriminator can be ANY JSON value — a map or list value must not crash the skip-log line or the ingest.
- An array element that is not a JSON object has no `"type"` field at all — count it as `:missing_type` and skip it (a bare string/number/null/array must never crash the ingest)
- A batch `insert_all` call fails → log the error, add the batch size to that schema's `:failed` count, and continue with remaining batches
