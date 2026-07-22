Build me an Elixir Phoenix JSON API for a two-level resource hierarchy — `Folder` and `Document` — with **cascading soft delete**. A folder owns many documents. Soft-deleting a folder must cascade the soft delete down to its documents, and restoring the folder must bring back exactly the documents that were removed *by that cascade* (not documents that were deleted on their own). The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

## Schemas

Create the schemas in a context module called `SoftCrud.Library`.

### `SoftCrud.Library.Folder` (table `folders`)

- `name` — string, required, non-empty
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

### `SoftCrud.Library.Document` (table `documents`)

- `title` — string, required, non-empty
- `content` — string, required
- `folder_id` — integer, required, references a `folders` row (a document always belongs to exactly one folder)
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `deleted_via_cascade` — boolean, **not null, defaults to `false`**. This flag records *how* a document became soft-deleted: `true` means it was removed as a side effect of its folder being soft-deleted, `false` means it is either live or was deleted on its own.
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create both tables with these columns. Add an index on each table's `deleted_at`, and an index on `documents.folder_id`.

## Context: `SoftCrud.Library`

### Folder functions

- `list_folders(opts \\ [])` — Returns all folders. By default excludes folders where `deleted_at` is not nil. With `include_deleted: true`, returns all folders.
- `get_folder(id, opts \\ [])` — Returns `{:ok, folder}` or `{:error, :not_found}`. By default a soft-deleted folder returns `{:error, :not_found}`; with `include_deleted: true` it is returned even if soft-deleted.
- `create_folder(attrs)` — Returns `{:ok, folder}` or `{:error, changeset}`. Validates that `name` is present and non-empty.
- `soft_delete_folder(folder)` — Cascading soft delete. Returns `{:ok, folder}`. It must:
  1. Set the folder's `deleted_at` to the current UTC time.
  2. For every document in that folder that is currently **live** (`deleted_at` is nil), set its `deleted_at` to the current UTC time and set `deleted_via_cascade` to `true`.
  3. Leave documents that were **already** soft-deleted untouched (their `deleted_at` and `deleted_via_cascade` do not change).
  - If the folder is already soft-deleted, this is a no-op that returns `{:ok, folder}` and touches no documents.
- `restore_folder(folder)` — Cascading restore. Returns `{:ok, folder}`. It must:
  1. Set the folder's `deleted_at` back to nil.
  2. For every document in that folder whose `deleted_via_cascade` is `true`, set `deleted_at` back to nil and `deleted_via_cascade` back to `false`.
  3. Leave documents that were deleted on their own (`deleted_via_cascade` is `false`) still soft-deleted.
  - If the folder is not soft-deleted, this is a no-op that returns `{:ok, folder}`.

### Document functions

- `list_documents(opts \\ [])` — Returns all documents. By default excludes documents where `deleted_at` is not nil. With `include_deleted: true`, returns all documents.
- `get_document(id, opts \\ [])` — Returns `{:ok, document}` or `{:error, :not_found}`. By default a soft-deleted document returns `{:error, :not_found}`; with `include_deleted: true` it is returned even if soft-deleted.
- `create_document(attrs)` — Returns `{:ok, document}` or `{:error, changeset}`. Validates that `title` is present and non-empty, `content` is present, and `folder_id` is present. A newly created document has `deleted_via_cascade` equal to `false`.
- `update_document(document, attrs)` — Updates only the document's `title` and/or `content`. Returns `{:ok, document}` or `{:error, changeset}`. Must **not** allow changing `folder_id`, `deleted_at`, or `deleted_via_cascade` through this function.
- `soft_delete_document(document)` — **Independent** soft delete: sets `deleted_at` to the current UTC time and sets `deleted_via_cascade` to `false`. Returns `{:ok, document}`. If already soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Sets `deleted_at` back to nil and `deleted_via_cascade` back to `false`. Returns `{:ok, document}`. If not soft-deleted, this is a no-op that returns the document as-is.

## Router & Controllers

Set up a JSON API under the `/api` scope.

### Folders

- `GET    /api/folders`             — Lists folders. Supports `?include_deleted=true`.
- `POST   /api/folders`             — Creates a folder. Body: `{"folder": {"name": "..."}}`. Success returns **201**.
- `GET    /api/folders/:id`         — Shows a folder. Supports `?include_deleted=true`.
- `DELETE /api/folders/:id`         — Cascading soft delete of the folder. Returns **200** with the folder JSON. Returns **404** if the folder does not exist or is already soft-deleted.
- `POST   /api/folders/:id/restore` — Cascading restore of the folder. Returns **200** with the folder JSON. If the folder is not soft-deleted, returns **200** as a no-op with the folder as-is.

### Documents

- `GET    /api/documents`             — Lists documents. Supports `?include_deleted=true`.
- `POST   /api/documents`             — Creates a document. Body: `{"document": {"title": "...", "content": "...", "folder_id": 1}}`. Success returns **201**.
- `GET    /api/documents/:id`         — Shows a document. Supports `?include_deleted=true`.
- `PUT    /api/documents/:id`         — Updates a document's `title` and/or `content`. Body: `{"document": {"title": "...", "content": "..."}}`. Returns **404** for a soft-deleted document (no `include_deleted` support on write endpoints). Any `folder_id`, `deleted_at`, or `deleted_via_cascade` in the body must be ignored.
- `DELETE /api/documents/:id`         — Independent soft delete of the document (sets `deleted_at`, `deleted_via_cascade` stays `false`). Returns **200** with the document JSON. Returns **404** if the document does not exist or is already soft-deleted.
- `POST   /api/documents/:id/restore` — Restores a soft-deleted document. Returns **200**. If not soft-deleted, returns **200** as a no-op with the document as-is.

### JSON shapes

Folder success responses render as:

```json
{ "data": { "id": 1, "name": "...", "deleted_at": null, "inserted_at": "...", "updated_at": "..." } }
```

Document success responses render as:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "folder_id": 1,
    "deleted_at": null,
    "deleted_via_cascade": false,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap in `{"data": [...]}`.

Validation errors return **422** with `{"errors": {...}}` containing field-level error details. Not-found responses return **404** with `{"errors": {"detail": "Not found"}}`.

## Project structure

Use the app name `soft_crud` with module prefix `SoftCrud`. Organize the code as:

- `lib/soft_crud/library.ex` — context module
- `lib/soft_crud/library/folder.ex` — Folder schema + changeset
- `lib/soft_crud/library/document.ex` — Document schema + changesets
- `lib/soft_crud_web/router.ex` — routes
- `lib/soft_crud_web/controllers/folder_controller.ex`
- `lib/soft_crud_web/controllers/folder_json.ex`
- `lib/soft_crud_web/controllers/document_controller.ex`
- `lib/soft_crud_web/controllers/document_json.ex`
- `lib/soft_crud_web/controllers/fallback_controller.ex`
- `lib/soft_crud_web/controllers/error_json.ex`
- `priv/repo/migrations/..._create_library.exs`

## Additional interface contract

- Use exactly these module names: router `SoftCrudWeb.Router`, context `SoftCrud.Library` (with `create_folder/1`, `create_document/1`, `soft_delete_folder/1`, `soft_delete_document/1` all returning `{:ok, struct}`), repo `SoftCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `SoftCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.