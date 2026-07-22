Build me an Elixir Phoenix JSON API for a **folder / document hierarchy** with *cascading* soft-delete support. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

Unlike a flat soft-delete resource, documents live **inside folders**, and soft-deleting a folder must cascade the deletion to the documents it contains. Restoring a folder must undo *only* the deletions that the cascade itself caused, leaving documents that were deleted independently untouched.

## Schemas

Create two schemas in a context module called `CascadeCrud.Content`.

### `CascadeCrud.Content.Folder` (table `folders`)

- `name` — string, required, non-empty
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

### `CascadeCrud.Content.Document` (table `documents`)

- `title` — string, required, non-empty
- `content` — string, required
- `folder_id` — integer, required, must reference an existing row in `folders`
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `deleted_cascade` — boolean, required, defaults to `false`. This flag records *how* a document became soft-deleted: `true` means it was soft-deleted as a side effect of its folder being soft-deleted (a cascade), `false` means it is either not deleted or was deleted directly.
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create both tables with these columns. Add a foreign key from `documents.folder_id` to `folders.id`, and add indexes on `documents.deleted_at`, `documents.folder_id`, and `folders.deleted_at`.

## Context: `CascadeCrud.Content`

### Folder functions

- `list_folders(opts \\ [])` — Returns all folders. By default, excludes folders where `deleted_at` is not nil. If `opts` contains `include_deleted: true`, return all folders.
- `get_folder(id, opts \\ [])` — Returns `{:ok, folder}` or `{:error, :not_found}`. By default a soft-deleted folder returns `{:error, :not_found}`. With `include_deleted: true`, return it even if soft-deleted.
- `create_folder(attrs)` — Creates a folder. Returns `{:ok, folder}` or `{:error, changeset}`. Validate that `name` is present and non-empty.
- `soft_delete_folder(folder)` — Sets the folder's `deleted_at` to the current UTC time **and cascades**: every document in that folder that is *not already soft-deleted* gets `deleted_at` set to the same time and `deleted_cascade` set to `true`. Documents that were already soft-deleted are left exactly as they are (their `deleted_cascade` value is not changed). Returns `{:ok, folder}`. If the folder is already soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).
- `restore_folder(folder)` — Sets the folder's `deleted_at` back to nil **and undoes its cascade**: every document in that folder with `deleted_cascade == true` is restored (`deleted_at` set to nil and `deleted_cascade` reset to `false`). Documents with `deleted_cascade == false` are left untouched — in particular, a document that was soft-deleted directly (not via cascade) stays soft-deleted. Returns `{:ok, folder}`. If the folder is not soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).

### Document functions

- `list_documents(opts \\ [])` — Returns all documents. By default, excludes documents where `deleted_at` is not nil. If `opts` contains `include_deleted: true`, return all documents regardless of `deleted_at`. If `opts` contains `folder_id: id`, return only documents belonging to that folder (combined with the delete filter).
- `get_document(id, opts \\ [])` — Returns `{:ok, document}` or `{:error, :not_found}`. By default a soft-deleted document returns `{:error, :not_found}`. With `include_deleted: true`, return it even if soft-deleted.
- `create_document(attrs)` — Creates a document. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, `content` is present, and `folder_id` is present and references an existing folder. A newly created document has `deleted_cascade == false`.
- `update_document(document, attrs)` — Updates an existing document. Only `title` and/or `content` may change; any other fields in `attrs` (such as `deleted_at`, `deleted_cascade`, or `folder_id`) are ignored. Returns `{:ok, document}` or `{:error, changeset}`.
- `soft_delete_document(document)` — Directly soft-deletes a single document: sets `deleted_at` to the current UTC time and sets `deleted_cascade` to `false` (a direct deletion is never a cascade). Returns `{:ok, document}`. If already soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Sets `deleted_at` back to nil and `deleted_cascade` to `false`. Returns `{:ok, document}`. If the document is not soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).

## Router & Controllers

Set up a JSON API under the `/api` scope with these endpoints.

### Folders

- `GET    /api/folders`              — Lists folders. Supports `?include_deleted=true`.
- `POST   /api/folders`              — Creates a folder. Body: `{"folder": {"name": "..."}}`. On success returns **201**.
- `GET    /api/folders/:id`          — Shows a folder. Supports `?include_deleted=true`. Returns 404 for a soft-deleted folder unless `include_deleted=true`.
- `DELETE /api/folders/:id`          — Soft-deletes a folder (cascading to its documents). Returns 200 with the folder JSON. Returns 404 if the folder does not exist or is already soft-deleted.
- `POST   /api/folders/:id/restore`  — Restores a soft-deleted folder (undoing its cascade). Returns 200 with the folder JSON. If the folder is not soft-deleted, return 200 as a no-op with the folder as-is. Returns 404 if the folder does not exist.

### Documents

- `GET    /api/documents`              — Lists documents. Supports `?include_deleted=true` and `?folder_id=ID`.
- `POST   /api/documents`              — Creates a document. Body: `{"document": {"title": "...", "content": "...", "folder_id": 1}}`. On success returns **201**.
- `GET    /api/documents/:id`          — Shows a document. Supports `?include_deleted=true`. Returns 404 for a soft-deleted document unless `include_deleted=true`.
- `PUT    /api/documents/:id`          — Updates a document's `title`/`content`. Returns 404 for a soft-deleted document (no `include_deleted` support on write endpoints).
- `DELETE /api/documents/:id`          — Directly soft-deletes a document. Returns 200 with the document JSON. Returns 404 if the document does not exist or is already soft-deleted.
- `POST   /api/documents/:id/restore`  — Restores a soft-deleted document. Returns 200 with the document JSON. If not soft-deleted, return 200 as a no-op. Returns 404 if the document does not exist.

### JSON shapes

A folder renders as:

```json
{ "data": { "id": 1, "name": "...", "deleted_at": null, "inserted_at": "...", "updated_at": "..." } }
```

A document renders as:

```json
{
  "data": {
    "id": 1,
    "title": "...",
    "content": "...",
    "folder_id": 1,
    "deleted_at": null,
    "deleted_cascade": false,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

List endpoints wrap the collection in `{"data": [...]}`.

Validation errors return 422 with `{"errors": {...}}` containing field-level detail. Not-found responses return 404 with `{"errors": {"detail": "Not found"}}`.

## Project structure

Use the app name `cascade_crud` with module prefix `CascadeCrud`. Organize the code as:

- `lib/cascade_crud/content.ex` — context module
- `lib/cascade_crud/content/folder.ex` — Folder schema + changeset
- `lib/cascade_crud/content/document.ex` — Document schema + changeset
- `lib/cascade_crud_web/router.ex` — routes
- `lib/cascade_crud_web/controllers/folder_controller.ex`
- `lib/cascade_crud_web/controllers/document_controller.ex`
- `lib/cascade_crud_web/controllers/folder_json.ex`
- `lib/cascade_crud_web/controllers/document_json.ex`
- `lib/cascade_crud_web/controllers/fallback_controller.ex`
- `lib/cascade_crud_web/controllers/error_json.ex`
- `priv/repo/migrations/..._create_content.exs` — migration

Use only standard Phoenix/Ecto dependencies. Give me all the files needed for a working application.

## Additional interface contract

- Use exactly these module names: router `CascadeCrudWeb.Router`, context `CascadeCrud.Content` (with `create_folder/1`, `create_document/1`, `soft_delete_folder/1`, and `soft_delete_document/1` returning `{:ok, ...}`), repo `CascadeCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `CascadeCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Successful creation returns **201** with the created resource JSON.