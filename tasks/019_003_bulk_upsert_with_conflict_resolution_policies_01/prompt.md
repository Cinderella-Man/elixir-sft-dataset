Write me a self-contained Elixir context module `Inventory` that performs a **bulk upsert** into an in-memory store keyed by a unique `"sku"`, with configurable conflict-resolution policies and per-item, index-aware result reporting.

This is a variation on a create-only bulk endpoint: here each item either **inserts** (new sku) or **updates** (existing sku), and the caller chooses how updates combine with the existing record.

**Store**
- Back the module with a named `Agent` started via `Inventory.start_link/0` (registered under the module name).
- Provide `Inventory.all/0`, `Inventory.count/0`, and `Inventory.get/1` (by sku).
- Each stored record is `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.

**Input shape**
- Each attribute map: `"sku"` (required, non-empty), `"name"` (required, 1–100 chars), `"price"` (required integer > 0), `"qty"` (optional non-negative integer, default `0`).

**`Inventory.bulk_upsert(list_of_attrs, opts \\ [])`**
- `opts[:on_conflict]` (default `:replace`) selects the update policy; anything other than `:replace | :merge | :skip` raises `ArgumentError`.
  - `:replace` — an existing sku is overwritten with the incoming record (qty = incoming qty).
  - `:merge` — an existing sku keeps its identity; `name`/`price` take the incoming values and `qty` **accumulates** (`existing.qty + incoming.qty`). This makes stock-receiving batches additive.
  - `:skip` — an existing sku is left untouched and reported as skipped.
- Processing is **in order**, so a repeated sku *within the same batch* is treated as a conflict against the running state (e.g., two `:merge` entries for the same sku accumulate).
- `opts[:partial]` (default `false`) selects the failure mode.
- Result tuples carry the zero-based input index: `{index, :inserted, record}`, `{index, :updated, record}`, `{index, :skipped, record}`, or `{index, :error, errors_map}`.
- The accompanying `record` is the record now in the store: for `:inserted` the newly inserted record, for `:updated` the resulting updated record, and for `:skipped` the existing record left in place (not the incoming attrs).
- The `errors_map` is keyed by the offending field's **string** name exactly as it appears in the input attrs, and each value is a list of human-readable message strings — e.g. `%{"name" => ["can't be blank"]}`.
- **Default (all-or-nothing):** if any item fails validation, write nothing and return `{:error, results}` where valid items appear as `{index, :ok, :valid}` and invalid ones as `{index, :error, errors}`. Otherwise apply all items in order and return `{:ok, results}`.
- **`partial: true`:** apply every valid item in order (insert/update/skip per policy and existence), report invalid items as errors, and return `{:ok, results}`.

Use only Elixir/OTP standard library — no external dependencies.
