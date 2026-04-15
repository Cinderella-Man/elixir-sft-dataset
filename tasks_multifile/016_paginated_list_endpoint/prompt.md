Write me a Phoenix controller module called `PaginatedListWeb.ItemController` that serves a `GET /api/items` endpoint returning paginated results from an Ecto schema.

I need the following pieces:

- An Ecto schema `PaginatedList.Item` backed by an `items` table with at minimum `:name` (string) and `:inserted_at` (utc_datetime_usec) fields. Include a basic migration to create the table.

- A context module `PaginatedList.Items` with a function `list_items(params)` that accepts a map with optional `"page"` and `"page_size"` string keys (as they come from query params). It should default `page` to 1 and `page_size` to 20. If `page_size` exceeds 100, clamp it to 100. If `page` or `page_size` are less than 1, default them to 1 and 20 respectively. The function must return a map with `:data` (the list of items for that page), `:meta` containing `:current_page`, `:page_size`, `:total_count`, and `:total_pages`. Items should be ordered by `inserted_at` ascending then by `id` ascending for deterministic ordering.

- A controller `PaginatedListWeb.ItemController` with an `index/2` action that reads `page` and `page_size` from `conn.params`, calls the context, and renders the JSON response. The JSON shape must be exactly:
  ```json
  {
    "data": [{"id": 1, "name": "...", "inserted_at": "..."}],
    "meta": {
      "current_page": 1,
      "page_size": 20,
      "total_count": 50,
      "total_pages": 3
    }
  }
  ```

- A JSON view or `Phoenix.Controller.json/2` call to render the response — either approach is fine.

- A router scope that mounts the endpoint at `/api/items`.

`total_pages` must be computed as `ceil(total_count / page_size)`. When there are zero items, `total_pages` should be 0. When the requested page is beyond `total_pages`, return an empty `data` list but still include correct metadata.

Use only standard Phoenix/Ecto — no external pagination libraries. Give me all the modules in separate files.