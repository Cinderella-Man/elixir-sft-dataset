Write me a self-contained Elixir module `QueryPaginator` that implements **offset pagination with multi-field sorting, filtering, and strict validation**. This is the query core of a `GET /api/items` list endpoint, implemented as a pure function over an in-memory list so it can be tested without a database. Unlike a plain paginator, this one validates its inputs and returns tagged error tuples on bad requests instead of silently coercing them.

Each item is a map with `:id` (integer), `:name` (string), and `:age` (integer).

I need `paginate(items, params)` returning `{:ok, %{data: [...], meta: %{...}}}` or `{:error, reason}`, where `params` is a map with optional string keys:

- `"page"` — default `1`; values `< 1` or non-numeric fall back to `1`.
- `"page_size"` — default `20`; clamp to a maximum of `100`; values `< 1` or non-numeric fall back to `20`.
- `"sort"` — the field to sort by. Allowed fields are exactly `"id"`, `"name"`, `"age"`. Any other value returns `{:error, :invalid_sort_field}`. Default `:id`.
- `"order"` — `"asc"` (default) or `"desc"`. Any other value returns `{:error, :invalid_order}`.
- `"min_age"` / `"max_age"` — optional integer filters, each an inclusive bound on `:age` (an item passes when `age >= min_age` and `age <= max_age`). A present-but-non-integer value returns `{:error, :invalid_filter}`.
- `"name_contains"` — optional case-insensitive substring filter on `:name`.

Validation happens before any work: if any of sort/order/filters are invalid, return the corresponding `{:error, reason}` and do NOT return partial data.

On success:
- Sorting is deterministic: sort by the chosen field, using `:id` ascending as the tiebreak; `"desc"` reverses the ordering. String fields sort by default term (codepoint) order, so uppercase names sort before lowercase ones.
- `total_count` is the count AFTER filtering. `total_pages` is `ceil(total_count / page_size)`, or `0` when there are zero matching items.
- `meta` includes `:current_page`, `:page_size`, `:total_count`, `:total_pages`, `:sort` (atom), `:order` (atom), and `:filters` (a map with `:min_age`, `:max_age`, `:name_contains`, each `nil` when unset).
- Requesting a page beyond `total_pages` returns an empty `data` list but still-correct metadata (mirror the base endpoint's behavior here).

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).
