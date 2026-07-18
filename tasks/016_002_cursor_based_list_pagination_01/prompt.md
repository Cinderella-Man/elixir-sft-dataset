Write me a self-contained Elixir module `CursorPaginator` that implements **cursor-based (keyset) pagination** — the pagination model used by large feeds and APIs where offset pagination is too expensive and unstable. This is the pagination core of a `GET /api/items` list endpoint, but implemented as a pure function over an in-memory list so it can be tested without a database.

I need the following:

- A function `paginate(items, params)` where `items` is a list of maps, each having at least an `:id` (integer) key, and `params` is a map with optional string keys as they would arrive from query params:
  - `"limit"` — page size. Default `20`. Clamp to a maximum of `100`. Values `< 1`, non-numeric, or not *fully* numeric (a value like `"12abc"` with trailing junk is rejected, not read as `12`) fall back to the default.
  - `"cursor"` — an **opaque** cursor string (see below). A missing cursor means start from the beginning. A malformed/undecodable cursor is treated gracefully as no cursor (start from the beginning) — it must NOT raise or return an error.
  - `"direction"` — `"next"` (default) or `"prev"`.

- Items are always ordered by `:id` ascending, regardless of the order of the input list.

- The result is a map `%{data: [...], meta: %{...}}` where `meta` contains exactly these five keys and no others (in particular, no `:total_count` or `:total_pages`):
  - `:page_size` — the effective limit.
  - `:next_cursor` — an opaque cursor pointing after the last returned item, or `nil` when there is nothing after the window.
  - `:prev_cursor` — an opaque cursor pointing before the first returned item, or `nil` when there is nothing before the window.
  - `:has_next` — boolean, whether items exist after the returned window.
  - `:has_prev` — boolean, whether items exist before the returned window.

- Forward paging (`"next"`) with cursor `c` returns the items with `id > c` (the first `limit` of them). Backward paging (`"prev"`) with cursor `c` returns the items with `id < c` — the LAST `limit` of them — still returned in ascending `:id` order.

- Unlike offset pagination there is **no** `total_count` or `total_pages`; correctness comes from the cursor boundary, so inserting/deleting rows between requests never skips or duplicates rows within a stable id ordering.

- Expose `encode_cursor(id)` and `decode_cursor(cursor)` as public helpers. The cursor must be opaque and URL-safe: it must contain only characters matching `[A-Za-z0-9_-]` (e.g. **unpadded** base64url of an internal representation — no `=` padding), must round-trip for any integer id (including `0`, negatives, and very large values), and must not embed the raw id as a literal substring. `decode_cursor/1` returns `{:ok, id}` for a valid cursor or `:error` for anything malformed; non-binary input (e.g. an integer) also returns `:error` rather than raising.

When `data` is empty, both cursors are `nil` and both booleans are `false`.

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).
