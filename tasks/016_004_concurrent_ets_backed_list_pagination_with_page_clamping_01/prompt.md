Write me a self-contained Elixir module `EtsCatalog` that implements **offset pagination over a concurrent, shared ETS-backed store**, with clamp-to-last-page semantics. This is the storage-and-listing core of a `GET /api/items` endpoint where many processes may be inserting items concurrently while pages are read. It must use ETS (not a database) so it stays self-contained and testable.

I need:

- `new()` — create and return a fresh ETS table handle backing the catalog. It must be an `:ordered_set` keyed by item id, and `:public` so that other processes can insert into it concurrently.

- `insert(table, item)` — insert a map that has at least an `:id` (integer) key, storing it under that id (later inserts with the same id overwrite). Returns `:ok`.

- `count(table)` — return the number of stored items.

- `list(table, params)` — offset pagination over a point-in-time snapshot of the table, ordered by id ascending. `params` is a map with optional string keys:
  - `"page"` — default `1`; `< 1` or non-numeric fall back to `1`.
  - `"page_size"` — default `20`; clamp to a maximum of `100`; `< 1` or non-numeric fall back to `20`.

  Returns `%{data: [...], meta: %{...}}` where `meta` contains:
  - `:requested_page` — the page the caller asked for (after coercion of bad values).
  - `:current_page` — the **effective** page actually served.
  - `:page_size`, `:total_count`, `:total_pages`.

The distinguishing behavior versus a plain paginator is **clamp-to-last-page**: when the requested page exceeds `total_pages`, do NOT return an empty list — clamp `current_page` down to `total_pages` and return that last page's items. When the catalog is empty, `current_page` is `1`, `total_pages` is `0`, and `data` is `[]`. `total_pages` is `ceil(total_count / page_size)`.

Because reads take a consistent snapshot (materialize and sort the current contents at call time), a `list/2` result is internally coherent even if concurrent inserts land during or after the call.

Use only the standard library (`:ets`). Give me the module in a single file.