Build me a self-contained Elixir in-memory context module for a `Document` resource with soft delete guarded by **optimistic concurrency** (version-checked writes). This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer`, which serializes writes so lost updates are provably impossible.

## Overview

Every document carries a monotonically increasing `lock_version` (starting at `0`). Each mutating operation — update, soft delete, restore — must be given the `expected_version` the caller last observed. If it does not match the document's current `lock_version`, the write is rejected with `{:error, :stale_version, current_version}` and no state changes. A successful mutation bumps `lock_version` by one. This lets many concurrent writers race safely: exactly one wins, the rest are told they hold a stale view.

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts \\ [])` takes no required options. `attrs` may use atom or string keys.

A document is a map: `%{id, title, content, deleted_at, lock_version, inserted_at, updated_at}` (`deleted_at` is `nil` when active, a stamp when soft-deleted).

Functions (server pid/ref first):

- `create_document(server, attrs)` — validates non-empty `title` and `content`. Returns `{:ok, document}` (with `lock_version: 0`) or `{:error, errors}`.
- `list_documents(server, opts \\ [])` — active only by default; `include_deleted: true` for all. Sorted by id.
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`; soft-deleted hidden unless `include_deleted: true`.
- `update_document(server, id, attrs, expected_version)` — updates `title`/`content` (partial allowed) of an active document. Precedence: `{:error, :not_found}` if missing **or** soft-deleted; then `{:error, :stale_version, current}` on version mismatch; then `{:error, errors}` on invalid attrs; else `{:ok, document}` with `lock_version + 1`. Never sets `deleted_at`.
- `soft_delete_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :already_deleted}` if already soft-deleted; else soft-deletes → `{:ok, document}` with `lock_version + 1`.
- `restore_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :not_deleted}` if already active; else restores → `{:ok, document}` with `lock_version + 1`.

Because the GenServer processes calls one at a time, a burst of concurrent `soft_delete_document(id, 0)` requests must yield exactly one `{:ok, _}` and the rest `{:error, :stale_version, 1}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.