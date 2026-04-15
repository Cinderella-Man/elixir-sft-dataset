Write me a Phoenix JSON API endpoint `GET /api/products` that supports searching, filtering, and sorting against a `products` table backed by Ecto and PostgreSQL.

## Schema and Migration

Create an Ecto schema `MyApp.Products.Product` with at least these fields:

- `name` — `:string`, required
- `category` — `:string`, required
- `price` — `:decimal`, required (stored as a numeric/decimal type, not float)

Also create the corresponding migration that creates the `products` table with those columns plus standard `inserted_at` / `updated_at` timestamps.

## Query Parameters

The endpoint must accept the following optional query parameters and apply them all together when multiple are present:

- **`name`** — partial, case-insensitive search on the product name. `?name=shoe` should match "Running Shoes", "SHOE rack", "snowshoe", etc. Use `ILIKE` with wildcards on both sides.

- **`category`** — exact match filter on the category field. `?category=electronics` matches only products whose category is literally `"electronics"`.

- **`min_price`** — inclusive lower bound on price. `?min_price=10` means `price >= 10`.

- **`max_price`** — inclusive upper bound on price. `?max_price=50` means `price <= 50`.

- **`sort`** — the field to sort by. Only the values `"name"`, `"price"`, and `"category"` are allowed. Any other value must cause the endpoint to return HTTP 400 with a JSON body `{"error": "invalid sort field"}`.

- **`order`** — sort direction, either `"asc"` or `"desc"`. Defaults to `"asc"` if `sort` is provided but `order` is not. If `order` is provided without `sort`, ignore it.

If no query parameters are provided, return all products with no particular ordering guarantee.

## Response Format

Always respond with HTTP 200 (except for the 400 case above) and a JSON body:

```json
{"data": [{"id": 1, "name": "Widget", "category": "gadgets", "price": "19.99"}, ...]}
```

Price should be serialized as a string to preserve decimal precision. An empty result set returns `{"data": []}` with status 200.

## Security

The sort field validation must act as an allowlist. Never interpolate user input directly into the query as a column name — convert the validated string to an existing atom and use that with Ecto's `order_by`. This prevents SQL injection through the sort parameter.

## Architecture

- Put the query-building logic in a context module `MyApp.Products` with a function like `list_products(params)` that accepts the params map and returns a list of `%Product{}` structs. Build the Ecto query by starting with `Product` and piping through conditional filter functions.
- The controller `MyAppWeb.ProductController` should have an `index/2` action that delegates to the context module and renders the result through a `MyAppWeb.ProductJSON` view module.
- Wire the route in the existing `:api` pipeline in the router.

## Constraints

- Use only Ecto and Phoenix (no external search libraries).
- The query must be a single composable Ecto query — no multiple round-trips to the database.
- All filtering and sorting happens at the database level, not in Elixir.

Give me all the files: migration, schema, context, controller, JSON view, and router addition. Each in its own code block with the file path as a comment at the top.