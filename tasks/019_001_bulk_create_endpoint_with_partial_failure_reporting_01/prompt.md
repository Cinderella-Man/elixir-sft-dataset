Write me an Elixir Phoenix JSON API endpoint at `POST /api/items/bulk` that accepts a JSON array of items to create, validates each item independently, and reports per-item success or failure with position indices.

I need the following pieces:

**Schema & Validation (`MyApp.Catalog.Item`):**
- Fields: `name` (string, required, 1–255 chars), `price` (integer, required, must be > 0), `description` (string, optional, max 1000 chars).
- Standard Ecto schema with a `changeset/2` function enforcing those validations.
- Timestamps.

**Context module (`MyApp.Catalog`):**
- `bulk_create_items(list_of_attrs, opts \\ [])` — takes a list of attribute maps and an options keyword list.
- When `partial: true` is **not** in opts (the default), wrap everything in a single `Repo.transaction`. If any item fails validation, roll back the entire transaction and return `{:error, results}` where `results` is a list of `{index, :ok, item}` or `{index, :error, changeset}` tuples. No rows should be inserted.
- When `partial: true` is in opts, insert each valid item individually (still inside a transaction per item for safety) and skip invalid ones. Return `{:ok, results}` with the same tuple format. Valid items are persisted; invalid ones are not.
- In both modes every entry in the results list must include the zero-based position index from the original input so the caller knows exactly which items succeeded or failed.

**Controller (`MyAppWeb.BulkItemController`):**
- `create/2` action handling `POST /api/items/bulk`.
- Read the `partial` query param (`?partial=true`). Anything other than the literal string `"true"` means all-or-nothing mode.
- Request body shape: `{"items": [ {…}, {…}, … ]}`. If the `"items"` key is missing or is not a list, return 400 with `{"error": "expected a list of items"}`.
- On all-or-nothing success: respond 201 with `{"status": "all_created", "items": [...]}` where each entry has `"index"`, `"id"`, `"name"`, `"price"`, `"description"`.
- On all-or-nothing failure: respond 422 with `{"status": "all_failed", "errors": [...]}` where each failed entry has `"index"` and `"errors"` (a map of field → list of messages), and each successful validation still appears with `"index"` and `"valid": true` (but nothing was inserted).
- On partial mode: respond 201 with `{"status": "partial", "created": [...], "errors": [...]}`. `created` holds the successfully inserted items with their indices; `errors` holds the failures with indices and per-field error messages.

**Router:** Mount the route as `post "/api/items/bulk", BulkItemController, :create` inside an `/api` scope with the `:api` pipeline.

Give me the complete modules in separate files. Use only Phoenix, Ecto, and standard library — no external dependencies. Assume a Postgres repo at `MyApp.Repo` already exists and is configured.