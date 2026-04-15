Build me an Elixir Phoenix JSON API for a `Document` resource with soft-delete support. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

## Schema

Create a `Document` schema in a context module called `SoftCrud.Documents` with the following fields:

- `title` — string, required, non-empty
- `content` — string, required
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create a `documents` table with these columns. Add an index on `deleted_at` to support efficient filtering.

## Context: `SoftCrud.Documents`

This module should expose the following functions:

- `list_documents(opts \\ [])` — Returns all documents. By default, excludes documents where `deleted_at` is not nil. If `opts` contains `include_deleted: true`, return all documents regardless of `deleted_at`.
- `get_document(id, opts \\ [])` — Fetches a single document by ID. Returns `{:ok, document}` or `{:error, :not_found}`. By default, a soft-deleted document should return `{:error, :not_found}`. If `opts` contains `include_deleted: true`, return it even if soft-deleted.
- `create_document(attrs)` — Creates a new document. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, and `content` is present.
- `update_document(document, attrs)` — Updates an existing document's `title` and/or `content`. Returns `{:ok, document}` or `{:error, changeset}`. Do not allow updating `deleted_at` through this function.
- `soft_delete_document(document)` — Sets `deleted_at` to the current UTC time. Returns `{:ok, document}`. If already soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Sets `deleted_at` back to nil. Returns `{:ok, document}`. If the document is not soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).

## Router & Controller

Set up a JSON API under the `/api` scope with these endpoints:

- `GET    /api/documents`              — Lists documents. Supports `?include_deleted=true` query param.
- `POST   /api/documents`              — Creates a document. Expects JSON body `{"document": {"title": "...", "content": "..."}}`.
- `GET    /api/documents/:id`          — Shows a single document. Supports `?include_deleted=true` query param.
- `PUT    /api/documents/:id`          — Updates a document. Expects JSON body `{"document": {"title": "...", "content": "..."}}`. Should return 404 for soft-deleted documents (no `include_deleted` support on write endpoints).
- `DELETE /api/documents/:id`          — Soft-deletes a document (sets `deleted_at`). Should return 200 with the updated document JSON. Should return 404 if already soft-deleted.
- `POST   /api/documents/:id/restore`  — Restores a soft-deleted document. Returns 200 with the restored document JSON. If the document is not soft-deleted, return 200 as a no-op with the document as-is.

All success responses should render the document as JSON with this shape:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "deleted_at": null,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap in `{"data": [...]}`.

Validation errors should return 422 with `{"errors": {...}}` containing field-level error details.

Not-found responses should return 404 with `{"errors": {"detail": "Not found"}}`.

## Project structure

Use the app name `soft_crud` with module prefix `SoftCrud`. Organize the code as:

- `lib/soft_crud/documents.ex` — context module
- `lib/soft_crud/documents/document.ex` — Ecto schema + changeset
- `lib/soft_crud_web/router.ex` — routes
- `lib/soft_crud_web/controllers/document_controller.ex` — controller
- `lib/soft_crud_web/controllers/document_json.ex` — JSON view/rendering
- `lib/soft_crud_web/controllers/fallback_controller.ex` — handles `{:error, ...}` tuples from the controller with proper HTTP status codes
- `priv/repo/migrations/..._create_documents.exs` — migration

Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.