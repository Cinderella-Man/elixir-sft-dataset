Build me an Elixir Phoenix JSON API for a two-level `Folder` → `Document` hierarchy with **cascading soft delete**. Soft-deleting a folder must cascade to the documents it contains, and restoring the folder must bring back *exactly* the documents that were removed by that cascade — nothing more. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

## Schemas

Create both schemas inside a context module called `SoftCrud.Documents`.

### `Folder` (`folders` table)

- `name` — string, required, non-empty
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

### `Document` (`documents` table)

- `title` — string, required, non-empty
- `content` — string, required
- `folder_id` — required; references a `Folder`. Every document belongs to exactly one folder.
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `cascaded` — boolean, required, **defaults to `false`**. This flag records *how* a document came to be soft-deleted: `true` means it was removed as a side effect of its folder being soft-deleted; `false` means it was either never deleted or was deleted directly (on its own). The flag is what lets a folder restore know which documents to bring back.
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The migration should create both tables. Add an index on `deleted_at` for both tables, and an index on `documents.folder_id`.

## Context: `SoftCrud.Documents`

### Folder functions

- `create_folder(attrs)` — Creates a folder. Returns `{:ok, folder}` or `{:error, changeset}`. Validate that `name` is present and non-empty.
- `list_folders(opts \\ [])` — Returns folders. By default excludes folders whose `deleted_at` is not nil. With `include_deleted: true`, returns all folders.
- `get_folder(id, opts \\ [])` — Returns `{:ok, folder}` or `{:error, :not_found}`. By default a soft-deleted folder returns `{:error, :not_found}`; with `include_deleted: true` it is returned even when soft-deleted.
- `soft_delete_folder(folder)` — Sets the folder's `deleted_at` to the current UTC time **and cascades**: every document in that folder that is currently *not* soft-deleted (`deleted_at` is nil) is soft-deleted too — its `deleted_at` is set to the same time and its `cascaded` flag is set to `true`. Documents that were already soft-deleted are left untouched. The whole operation is atomic. Returns `{:ok, folder}`. If the folder is already soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).
- `restore_folder(folder)` — Sets the folder's `deleted_at` back to nil **and cascade-restores**: every document in that folder whose `cascaded` flag is `true` is restored — its `deleted_at` is set back to nil and its `cascaded` flag is reset to `false`. Documents whose `cascaded` flag is `false` are left untouched (a document deleted on its own before the cascade stays deleted). The whole operation is atomic. Returns `{:ok, folder}`. If the folder is not soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).

### Document functions

- `create_document(attrs)` — Creates a document. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, `content` is present, and `folder_id` is present. New documents start with `deleted_at: nil` and `cascaded: false`.
- `list_documents(opts \\ [])` — Returns documents. By default excludes documents whose `deleted_at` is not nil. With `include_deleted: true`, returns all documents.
- `get_document(id, opts \\ [])` — Returns `{:ok, document}` or `{:error, :not_found}`. By default a soft-deleted document returns `{:error, :not_found}`; with `include_deleted: true` it is returned even when soft-deleted.
- `soft_delete_document(document)` — Directly soft-deletes a single document: sets `deleted_at` to the current UTC time and sets `cascaded` to `false` (a direct deletion, not a cascade). Returns `{:ok, document}`. If already soft-deleted, this is a no-op returning the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Directly restores a single document: sets `deleted_at` back to nil and `cascaded` to `false`. Returns `{:ok, document}`. If the document is not soft-deleted, this is a no-op returning the document as-is (still `{:ok, document}`).

## Router & Controllers

Set up a JSON API under the `/api` scope.

### Folders

- `GET    /api/folders`             — Lists folders. Supports `?include_deleted=true`.
- `POST   /api/folders`             — Creates a folder. Body: `{"folder": {"name": "..."}}`. On success returns **201** with the folder JSON.
- `GET    /api/folders/:id`         — Shows a folder. Supports `?include_deleted=true`. 404 for a soft-deleted folder unless `include_deleted=true`.
- `DELETE /api/folders/:id`         — Soft-deletes the folder (cascading to its documents). Returns 200 with the updated folder JSON. Returns 404 if the folder does not exist or is already soft-deleted.
- `POST   /api/folders/:id/restore` — Restores a soft-deleted folder (cascade-restoring its cascade-deleted documents). Returns 200 with the folder JSON. If the folder is not soft-deleted, returns 200 as a no-op with the folder as-is. Returns 404 if the folder does not exist.

### Documents

- `GET    /api/documents`             — Lists documents. Supports `?include_deleted=true`.
- `POST   /api/documents`             — Creates a document. Body: `{"document": {"title": "...", "content": "...", "folder_id": 1}}`. On success returns **201** with the document JSON.
- `GET    /api/documents/:id`         — Shows a document. Supports `?include_deleted=true`. 404 for a soft-deleted document unless `include_deleted=true`.
- `DELETE /api/documents/:id`         — Directly soft-deletes the document. Returns 200 with the updated document JSON. Returns 404 if the document does not exist or is already soft-deleted.
- `POST   /api/documents/:id/restore` — Directly restores a soft-deleted document. Returns 200 with the document JSON. If the document is not soft-deleted, returns 200 as a no-op with the document as-is. Returns 404 if the document does not exist.

### JSON shapes

Folder:

```json
{
  "data": {
    "id": 1,
    "name": "...",
    "deleted_at": null,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

Document:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "folder_id": 1,
    "deleted_at": null,
    "cascaded": false,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap the array in `{"data": [...]}`.

Validation errors return 422 with `{"errors": {...}}` containing field-level details. Not-found responses return 404 with `{"errors": {"detail": "Not found"}}`.

## Project structure

Use the app name `soft_crud` with module prefix `SoftCrud`. Organize the code as:

- `lib/soft_crud/documents.ex` — context module
- `lib/soft_crud/documents/folder.ex` — Folder schema + changeset
- `lib/soft_crud/documents/document.ex` — Document schema + changeset
- `lib/soft_crud_web/router.ex` — routes
- `lib/soft_crud_web/controllers/folder_controller.ex` — folder controller
- `lib/soft_crud_web/controllers/document_controller.ex` — document controller
- `lib/soft_crud_web/controllers/folder_json.ex` — folder JSON rendering
- `lib/soft_crud_web/controllers/document_json.ex` — document JSON rendering
- `lib/soft_crud_web/controllers/fallback_controller.ex` — handles `{:error, ...}` tuples
- `priv/repo/migrations/..._create_documents.exs` — migration

## Additional interface contract

- Use exactly these module names: router `SoftCrudWeb.Router`, context `SoftCrud.Documents` (with `create_folder/1`, `create_document/1`, `soft_delete_folder/1`, `restore_folder/1`, `soft_delete_document/1`, `restore_document/1` all returning `{:ok, _}` on success), repo `SoftCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `SoftCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Successful creation returns **201** with the JSON.

Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.