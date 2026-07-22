# Task 17 — V3: Relevance-Ranked Full-Text Search

Write me a self-contained Elixir context module `Catalog.Ranked` that searches a product catalog by **free-text relevance**: it tokenizes a query, scores each product across weighted fields (name weighted higher than description), and orders results by that relevance score — replacing the base task's simple `ILIKE` substring filter with an actual ranking algorithm.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 1, name: "Running Shoes", description: "Lightweight shoes for running and trail",
  category: "footwear", price_cents: 8999}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Ranked.search(products, params)` returning:

- `{:ok, %{data: [...]}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map. Each `data` item is `%{id, name, category, price, score}` where `price` is a two-decimal dollar string and `score` is the computed integer relevance score.

## Search & scoring

- **`"q"`** — the free-text query. Tokenize by downcasing and splitting on any run of non-alphanumeric characters (so `"Running, shoes!"` ⇒ `["running", "shoes"]`).
- Tokenize each product's `name` and `description` the same way.
- **Prefix matching**: a query token matches a document token when the document token **starts with** the query token (so `"run"` matches `"running"`, and `"work"` matches `"workouts"`).
- **Score** = for each query token, `3 × (number of name tokens it prefix-matches) + 1 × (number of description tokens it prefix-matches)`, summed over all query tokens. Name matches are weighted 3×; multiple matches accumulate.
- When `"q"` is present and non-empty, **only products with a score greater than 0 are returned** (it acts as the search filter). When `"q"` is absent or empty, all products pass with score `0`.

## Pre-filters (applied before scoring)

- **`"category"`** — exact match.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank ignored.

## Sorting

- **`"sort"`** — allowlist of exactly `"relevance"`, `"name"`, `"price"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"relevance"`.
- **`"order"`** — `"asc"` or `"desc"`.
  - For `"relevance"`, the default direction is **descending** (highest score first); an explicit `"asc"` reverses it. Ties broken by `name` ascending, then `id` ascending.
  - For `"name"` / `"price"`, the default is ascending; ties broken by `id` ascending.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Scoring, prefix matching, field weighting, and ordering all happen inside the module.