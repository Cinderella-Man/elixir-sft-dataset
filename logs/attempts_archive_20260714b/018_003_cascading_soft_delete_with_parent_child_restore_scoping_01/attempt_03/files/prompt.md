Build me an Elixir Phoenix JSON API for a `Document` resource that supports **cascading soft delete** across a parent/child hierarchy. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

Documents form a tree: a document may have a `parent_id` pointing at another document (or `nil` for a root document). When you soft-delete a document, the whole subtree beneath it is soft-deleted too. Restoring is *scoped*: it only brings back the descendants that were taken down by that cascade — descendants a user had already deleted on their own stay deleted.

## Schema

Create a `Document` schema in a context module called `CascadeCrud.Documents` with the following fields:

- `title` — string, required, non-empty
- `content` — string, required
- `parent_id` — integer id of another document, nullable (nil for a root document)
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `deleted_via_cascade` — boolean, defaults to `false`. Marks *why* a document is currently soft-deleted:
  - `false` — either the document is live, or it was deleted **directly** (an explicit deletion of this exact document).
  - `true` — the document was deleted **only** because an ancestor was deleted (a cascade).
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create a `documents` table with these columns. Add an index on `deleted_at` and an index on `parent_id`.

## Context: `CascadeCrud.Documents`

This module should expose the following functions:

- `list_documents(opts \\ [])` — Returns all documents. By default, excludes any document whose `deleted_at` is not nil. If `opts` contains `include_deleted: true`, return all documents regardless of `deleted_at`.
- `get_document(id, opts \\ [])` — Fetches a single document by ID. Returns `{:ok, document}` or `{:error, :not_found}`. By default, a soft-deleted document returns `{:error, :not_found}`. If `opts` contains `include_deleted: true`, return it even if soft-deleted.
- `create_document(attrs)` — Creates a new document. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, and `content` is present. `parent_id` is optional; when supplied it must reference an existing, **non-soft-deleted** document — otherwise return `{:error, changeset}` with a field-level error on `parent_id`. A newly created document has `deleted_at: nil` and `deleted_via_cascade: false`.
- `update_document(document, attrs)` — Updates an existing document's `title` and/or `content`. Returns `{:ok, document}` or `{:error, changeset}`. Do NOT allow updating `parent_id`, `deleted_at`, or `deleted_via_cascade` through this function (those attributes are ignored).
- `soft_delete_document(document)` — Soft-deletes the given document **and cascades** to its whole subtree:
  - The document you pass in is flagged `deleted_at: <now>`, `deleted_via_cascade: false` (an explicit deletion).
  - Every descendant (children, grandchildren, …) that is **not already soft-deleted** is flagged `deleted_at: <now>`, `deleted_via_cascade: true`.
  - Descendants that were already soft-deleted keep their existing state untouched.
  - Returns `{:ok, document}`. If the document is already soft-deleted, this is a no-op that returns `{:ok, document}` as-is.
- `restore_document(document)` — Restores a soft-deleted document. Returns `{:ok, document}`, `{:error, :parent_deleted}`, and:
  - If the document is not soft-deleted, this is a no-op that returns `{:ok, document}` as-is.
  - If the document's parent is currently soft-deleted, restoring would create a visible document under a deleted parent, so return `{:error, :parent_deleted}` and change nothing.
  - Otherwise, set the document's `deleted_at` back to nil and `deleted_via_cascade` to false, then **cascade the restore downward**: a descendant is restored (its `deleted_at` set to nil, `deleted_via_cascade` set to false) only if it was removed by the cascade (`deleted_via_cascade == true`) **and** its own parent has just been restored. A descendant that had been deleted directly (`deleted_via_cascade == false`) is left deleted, and the restore does not propagate any further beneath it.

## Router & Controller

Set up a JSON API under the `/api` scope with these endpoints:

- `GET    /api/documents`              — Lists documents. Supports `?include_deleted=true` query param.
- `POST   /api/documents`              — Creates a document. Expects JSON body `{"document": {"title": "...", "content": "...", "parent_id": 1}}` (`parent_id` optional).
- `GET    /api/documents/:id`          — Shows a single document. Supports `?include_deleted=true` query param.
- `PUT    /api/documents/:id`          — Updates a document (`title`/`content` only). Returns 404 for soft-deleted documents (no `include_deleted` support on write endpoints).
- `DELETE /api/documents/:id`          — Soft-deletes a document and cascades to its subtree. Returns 200 with the deleted document JSON. Returns 404 if the document does not exist or is already soft-deleted.
- `POST   /api/documents/:id/restore`  — Restores a soft-deleted document (with scoped cascade restore). Returns 200 with the restored document JSON. If the document is not soft-deleted, return 200 as a no-op with the document as-is. Returns 404 if the document does not exist. Returns **409** if the document's parent is currently soft-deleted.

All success responses render the document as JSON with this shape:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "parent_id": null,
    "deleted_at": null,
    "deleted_via_cascade": false,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap in `{"data": [...]}`.

Validation errors return 422 with `{"errors": {...}}` containing field-level error details.
Not-found responses return 404 with `{"errors": {"detail": "Not found"}}`.
Conflict responses (restoring a document whose parent is soft-deleted) return 409 with `{"errors": {"detail": "Parent is deleted"}}`.

## Project structure

Use the app name `cascade_crud` with module prefix `CascadeCrud`. Organize the code as:

- `lib/cascade_crud/documents.ex` — context module
- `lib/cascade_crud/documents/document.ex` — Ecto schema + changesets
- `lib/cascade_crud_web/router.ex` — routes
- `lib/cascade_crud_web/controllers/document_controller.ex` — controller
- `lib/cascade_crud_web/controllers/document_json.ex` — JSON view/rendering
- `lib/cascade_crud_web/controllers/fallback_controller.ex` — handles `{:error, ...}` tuples from the controller with proper HTTP status codes
- `priv/repo/migrations/..._create_documents.exs` — migration

Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.

## Additional interface contract

- Use exactly these module names: router `CascadeCrudWeb.Router`, context `CascadeCrud.Documents` (with `create_document/1` returning `{:ok, doc}`, and `soft_delete_document/1` / `restore_document/1` returning `{:ok, doc}`), repo `CascadeCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `CascadeCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Successful creation returns **201** with the document JSON.