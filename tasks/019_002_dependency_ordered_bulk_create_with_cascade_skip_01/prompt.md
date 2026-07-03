Write me a self-contained Elixir context module `Catalog` that performs **dependency-ordered bulk creation** of catalog entries into an in-memory store, with per-item, index-aware result reporting.

This is a variation on a plain bulk-create endpoint: here the items in a single batch may reference **other items in the same batch** as their parent, so the module must resolve those references, create entries in a valid topological order, detect cycles, and — in partial mode — cascade-skip the dependents of any item that fails.

**Store**
- Back the module with a named `Agent` started via `Catalog.start_link/0` (registered under the module name).
- Provide `Catalog.all/0` (list of stored items), `Catalog.count/0`, and `Catalog.get/1` (by id).
- Each stored item is a map `%{id: integer, name: String.t(), ref: String.t() | nil, parent_id: integer | nil}` with an auto-incrementing integer `id`.

**Input shape**
- Each attribute map may contain: `"name"` (required, 1–100 chars), `"ref"` (optional string — a temporary in-batch identifier), and `"parent"` (optional string — a reference to another item's `"ref"` in the same batch; `nil`/absent means a root item).

**`Catalog.bulk_create(list_of_attrs, opts \\ [])`**
Compute per-item validity and dependency status, then:

- Every result carries the zero-based position index from the original input. Result tuples are:
  - `{index, :ok, item}` — created (or `{index, :ok, :valid}` when validated-but-not-stored in an all-or-nothing rollback),
  - `{index, :error, reason}` — where `reason` is `{:validation, errors_map}`, `:duplicate_ref`, `:unknown_parent`, or `:cycle`,
  - `{index, :skipped, ancestor_index}` — a valid item skipped because an ancestor was bad/skipped.
- **Default (all-or-nothing):** if *any* item is bad (invalid, duplicate ref, unknown parent) or involved in a cycle — meaning not every item is creatable — roll everything back (store nothing) and return `{:error, results}`. If every item is creatable, create them all in dependency order (parents before children, resolving `parent_id` to the real created id) and return `{:ok, results}`.
- **`partial: true`:** create every creatable item in dependency order; bad items are reported as errors and their transitive dependents are reported as `:skipped` (with the index of the nearest bad/skipped ancestor). Return `{:ok, results}`.

Cycle detection must mark exactly the items **on** a cycle as `:cycle`; items merely downstream of a cycle are `:skipped`. Use only Elixir/OTP standard library — no external dependencies.