# Task 17 — V2: Faceted Search with Multi-Value Filters and Facet Counts

Write me a self-contained Elixir context module `Catalog.Faceted` that implements **faceted search** over a product catalog: multi-value (OR) category filters, multi-tag (AND) filters, and — the defining feature — **facet counts** returned alongside the results so a UI can render "drill-down" filters without dead-ends.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999, tags: ["wireless", "office"]}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Faceted.search(products, params)` returning:

- `{:ok, %{data: [...], facets: %{categories: %{...}, tags: %{...}}, total: integer}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map.

## Filtering

- **`"name"`** — partial, case-insensitive substring match on the name.
- **`"categories"`** — a **list** of category strings; a product matches if its category is **any** of them (OR). Absent/empty list ⇒ no category constraint.
- **`"tags"`** — a **list** of tag strings; a product matches only if it contains **all** of them (AND). Absent/empty list ⇒ no tag constraint.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank values are ignored.

`total` is the count of products passing **all** filters, and `data` is that same fully-filtered set (sorted).

## Facet counts (the key semantics)

Each facet reports how many products **would** match if the caller added values to *that* facet, so a facet's own selection must **not** constrain its own counts, while **every other** active filter still applies:

- **`facets.categories`** — a map of `category => count` computed over products passing every filter **except** the `"categories"` filter.
- **`facets.tags`** — a map of `tag => count` (each product contributes to one entry per tag it carries) computed over products passing every filter **except** the `"tags"` filter.

So selecting a category must not zero-out the other categories in `facets.categories` (the user can still widen the OR), but selecting a tag *does* shrink `facets.categories`, because the tag filter is a "different" filter that still applies. Facets never include entries with a zero count.

## Sorting

- **`"sort"`** — allowlist of exactly `"name"`, `"price"`, `"id"`, `"category"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"id"`.
- **`"order"`** — `"asc"` (default) or `"desc"`; ties broken by `id` in the same direction.

## Response format

Each item in `data` is `%{id, name, category, price, tags}` where `price` is a two-decimal dollar string. An empty result returns `data: []`, `total: 0`, and facets reflecting the remaining source sets.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Facet counts must be computed by excluding exactly the corresponding facet's own filter and no other.