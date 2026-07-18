# Task 17 — V1: Keyset (Cursor) Pagination Search

Write me a self-contained Elixir context module `Catalog.KeysetSearch` that searches, filters, sorts, and **paginates** a product catalog using **keyset (cursor) pagination** instead of returning the whole result set.

To keep the module dependency-free and autotestable, it operates over an **in-memory list of product maps** rather than a live database. Each product is a map:

```elixir
%{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999}
```

Prices are stored as **integer cents** to preserve precision (no floats, no Decimal).

## Public API

Implement `Catalog.KeysetSearch.search(products, params)` where `products` is a list of the maps above and `params` is a string-keyed map (like decoded query params). It returns:

- `{:ok, %{data: [...], next_cursor: cursor_or_nil, has_more: boolean}}` on success, or
- `{:error, :invalid_sort_field}` / `{:error, :invalid_cursor}` on failure.

## Filtering (all applied together when present)

- **`"name"`** — partial, case-insensitive substring match on the product name.
- **`"category"`** — exact match on the category field.
- **`"min_price"`** — inclusive lower bound, an integer-cents string (e.g. `"1000"` = $10.00). Unparseable/blank values are ignored.
- **`"max_price"`** — inclusive upper bound, integer-cents string. Unparseable/blank values are ignored.

## Sorting

- **`"sort"`** — allowlist of exactly `"name"`, `"price"`, `"id"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"id"`.
- **`"order"`** — `"asc"` (default) or `"desc"`.
- Sorting is **stable and total**: ties on the sort field are broken by `id` in the same direction as `order`.

## Keyset pagination

- **`"limit"`** — page size (integer or integer string). Default `3`, clamped to a max of `100`; non-positive/garbage falls back to the default.
- **`"cursor"`** — an **opaque** token. When present, the page contains only the items that fall **strictly after** the cursor in the current ordering (by `(sort_value, id)`), never using numeric offsets.
- `next_cursor` is a fresh opaque token derived from the **last item on the returned page**, or `nil` when no further items remain. `has_more` reflects whether items remain beyond this page.
- The cursor must encode the **sort field** it was produced under. If a cursor is presented alongside a *different* `sort`, return `{:error, :invalid_cursor}`. A structurally malformed cursor is also `{:error, :invalid_cursor}`. This prevents callers from paginating incoherently across mismatched orderings.

## Response format

Each item in `data` is `%{id: ..., name: ..., category: ..., price: ...}` where `price` is a dollar string like `"29.99"` (cents formatted with two decimal places). An empty page returns `%{data: [], next_cursor: nil, has_more: false}`.

## Constraints

- Pure Elixir, standard library only. No Ecto, no Decimal, no Phoenix.
- Cursors must be self-describing and validated (do not trust arbitrary decoded content).
- Filtering, sorting, and cursor slicing must all be handled in the module — the caller passes params and gets a page back.