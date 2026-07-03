Build me a self-contained Elixir in-memory context module for a `Document` resource with **trash-and-purge soft delete** governed by a retention window. This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer` and time is injectable so retention can be tested deterministically.

## Overview

Unlike a plain `deleted_at` flag, a soft-deleted ("trashed") document has a *bounded* second life: it can be restored only while it is inside its retention window. Once `retention_ms` has elapsed since it was trashed, the document becomes **expired** — no longer restorable — and is eligible to be permanently **purged**. This gives three derived states from a single `deleted_at` field plus the clock:

- `:active`  — `deleted_at == nil`
- `:trashed` — `deleted_at` set and `now - deleted_at < retention_ms`
- `:expired` — `deleted_at` set and `now - deleted_at >= retention_ms`

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts)` accepts:

- `:clock` — a zero-arity function returning the current time in integer milliseconds (default `fn -> System.system_time(:millisecond) end`).
- `:retention_ms` — how long a trashed document stays restorable (default 30 days).

A document is a map: `%{id, title, content, deleted_at, inserted_at, updated_at}` where timestamps come from the injected clock.

Functions (all take the server pid/ref first):

- `create_document(server, attrs)` — validates `title` (non-empty string) and `content` (non-empty string). Returns `{:ok, document}` or `{:error, errors}` where `errors` is a map like `%{title: ["can't be blank"]}`. `attrs` may use atom or string keys.
- `list_documents(server, opts \\ [])` — returns documents sorted by id. By default only `:active`. With `include_deleted: true`, returns active, trashed, and expired (anything still stored).
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`. By default a trashed or expired document returns `{:error, :not_found}`; with `include_deleted: true` it is returned.
- `update_document(server, id, attrs)` — updates `title` and/or `content` (partial updates allowed) of an `:active` document. Returns `{:ok, document}`, `{:error, errors}`, or `{:error, :not_found}` if the document is missing, trashed, or expired. `deleted_at` can never be set through this function.
- `soft_delete_document(server, id)` — sets `deleted_at` to `clock.()` for an active document → `{:ok, document}`. If already trashed/expired, no-op returning `{:ok, document}`. `{:error, :not_found}` if missing.
- `restore_document(server, id)` — clears `deleted_at` of a `:trashed` document → `{:ok, document}`. No-op `{:ok, document}` for an already-active document. Returns `{:error, :expired}` for an expired document (retention lapsed). `{:error, :not_found}` if missing.
- `purge_document(server, id)` — hard-deletes a trashed or expired document, returning `{:ok, document}`. Returns `{:error, :not_deleted}` for an active document and `{:error, :not_found}` if missing.
- `purge_expired(server)` — permanently removes every currently `:expired` document. Returns `{:ok, purged_count}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.