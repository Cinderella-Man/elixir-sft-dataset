Build me an Elixir Phoenix JSON API for a two-level `Folder` → `Document` hierarchy with **cascading soft-delete** support. The project should be a standard Mix project using Phoenix and Ecto with PostgreSQL.

The defining feature of this variation is the cascade: soft-deleting a folder soft-deletes the documents inside it, and restoring the folder brings back **only** the documents that were removed as part of that cascade — documents that had already been soft-deleted on their own stay deleted.

## Schemas

### `Folder` (in context `SoftCrud.Library`, module `SoftCrud.Library.Folder`)

- `name` — string, required, non-empty
- `deleted_at` — utc_datetime, nullable, defaults to nil
- `inserted_at` / `updated_at` — standard Phoenix timestamps

### `Document` (module `SoftCrud.Library.Document`)

- `title` — string, required, non-empty
- `content` — string, required
- `folder_id` — belongs to a `Folder` (required)
- `deleted_at` — utc_datetime, nullable, defaults to nil
- an internal boolean used to remember whether a document's current soft-deletion happened via a folder cascade (defaults to false). This flag is **not** part of any JSON response.
- `inserted_at` / `updated_at` — standard Phoenix timestamps

The Ecto migration should create `folders` and `documents` tables with these columns, a foreign key from `documents.folder_id` to `folders.id`, and an index on each table's `deleted_at`.

## Context: `SoftCrud.Library`

### Folder functions

- `list_folders(opts \\ [])` — Returns folders. By default excludes folders where `deleted_at` is not nil. With `include_deleted: true`, returns all folders.
- `get_folder(id, opts \\ [])` — Returns `{:ok, folder}` or `{:error, :not_found}`. By default a soft-deleted folder returns `{:error, :not_found}`; with `include_deleted: true` it is returned even if soft-deleted.
- `create_folder(attrs)` — Returns `{:ok, folder}` or `{:error, changeset}`. Validate that `name` is present and non-empty.
- `soft_delete_folder(folder)` — Sets the folder's `deleted_at` to the current UTC time. **Cascade:** every document in that folder that is not already soft-deleted is soft-deleted at the same time and marked as having been removed by this cascade. Documents that were already soft-deleted before the folder was deleted are left untouched. Returns `{:ok, folder}`. If the folder is already soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).
- `restore_folder(folder)` — Sets the folder's `deleted_at` back to nil. **Selective restore:** only the documents that were soft-deleted as part of this folder's cascade are restored along with it (their `deleted_at` goes back to nil). Documents that had been soft-deleted independently before the cascade remain soft-deleted. Returns `{:ok, folder}`. If the folder is not soft-deleted, this is a no-op that returns the folder as-is (still `{:ok, folder}`).

### Document functions

- `list_documents(folder_id, opts \\ [])` — Returns the documents belonging to the folder with that id. By default excludes documents where `deleted_at` is not nil. With `include_deleted: true`, returns all of that folder's documents.
- `get_document(id, opts \\ [])` — Returns `{:ok, document}` or `{:error, :not_found}`. By default a soft-deleted document returns `{:error, :not_found}`; with `include_deleted: true` it is returned even if soft-deleted.
- `create_document(folder, attrs)` — Creates a document inside the given folder. Returns `{:ok, document}` or `{:error, changeset}`. Validate that `title` is present and non-empty, and `content` is present.
- `update_document(document, attrs)` — Updates an existing document's `title` and/or `content`. Returns `{:ok, document}` or `{:error, changeset}`. Do not allow updating `deleted_at` through this function.
- `soft_delete_document(document)` — Soft-deletes a single document on its own (an independent delete, **not** a cascade). Sets `deleted_at` to the current UTC time. Returns `{:ok, document}`. If already soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).
- `restore_document(document)` — Sets `deleted_at` back to nil. Returns `{:ok, document}`. If the document is not soft-deleted, this is a no-op that returns the document as-is (still `{:ok, document}`).

## Router & Controller

Set up a JSON API under the `/api` scope.

### Folder endpoints

- `GET    /api/folders`               — Lists folders. Supports `?include_deleted=true`.
- `POST   /api/folders`               — Creates a folder. Expects JSON body `{"folder": {"name": "..."}}`. Returns **201**.
- `GET    /api/folders/:id`           — Shows a single folder. Supports `?include_deleted=true`.
- `DELETE /api/folders/:id`           — Soft-deletes the folder (cascading to its documents). Returns 200 with the updated folder JSON. Returns 404 if the folder does not exist or is already soft-deleted.
- `POST   /api/folders/:id/restore`   — Restores a soft-deleted folder (and its cascaded documents). Returns 200 with the restored folder JSON. If the folder is not soft-deleted, returns 200 as a no-op with the folder as-is.

### Document endpoints

- `GET    /api/folders/:folder_id/documents` — Lists the documents in a folder. Supports `?include_deleted=true`. Returns 404 if the folder does not exist or is soft-deleted.
- `POST   /api/folders/:folder_id/documents` — Creates a document in a folder. Expects JSON body `{"document": {"title": "...", "content": "..."}}`. Returns **201**. Returns 404 if the folder does not exist or is soft-deleted.
- `GET    /api/documents/:id`          — Shows a single document. Supports `?include_deleted=true`.
- `PUT    /api/documents/:id`          — Updates a document's `title` and/or `content`. Expects JSON body `{"document": {...}}`. Returns 404 for soft-deleted documents (no `include_deleted` support on write endpoints).
- `DELETE /api/documents/:id`          — Soft-deletes a single document (independent delete). Returns 200 with the updated document JSON. Returns 404 if the document does not exist or is already soft-deleted.
- `POST   /api/documents/:id/restore`  — Restores a soft-deleted document. Returns 200 with the restored document JSON. If the document is not soft-deleted, returns 200 as a no-op with the document as-is.

### JSON shapes

Folder success responses render as:

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

Document success responses render as:

```json
{
  "data": {
    "id": 1,
    "folder_id": 1,
    "title": "...",
    "content": "...",
    "deleted_at": null,
    "inserted_at": "...",
    "updated_at": "..."
  }
}
```

For list endpoints, wrap in `{"data": [...]}`.

Validation errors return 422 with `{"errors": {...}}` containing field-level error details. Not-found responses return 404 with `{"errors": {"detail": "Not found"}}`.

## Cascade & restore semantics (summary)

- Soft-deleting a folder makes the folder and all of its currently-visible documents disappear from default listings (each affected document gets a non-null `deleted_at`).
- Restoring that folder makes it and the cascade-deleted documents visible again.
- A document that was soft-deleted **independently** (via `DELETE /api/documents/:id`) *before* its folder was soft-deleted stays soft-deleted after the folder is restored — the folder restore does not resurrect it.

## Project structure

Use the app name `soft_crud` with module prefix `SoftCrud`. Organize the code as:

- `lib/soft_crud/library.ex` — context module
- `lib/soft_crud/library/folder.ex` — Folder schema + changeset
- `lib/soft_crud/library/document.ex` — Document schema + changeset
- `lib/soft_crud_web/router.ex` — routes
- `lib/soft_crud_web/controllers/folder_controller.ex` — folder controller
- `lib/soft_crud_web/controllers/document_controller.ex` — document controller
- `lib/soft_crud_web/controllers/folder_json.ex` — folder JSON rendering
- `lib/soft_crud_web/controllers/document_json.ex` — document JSON rendering
- `lib/soft_crud_web/controllers/fallback_controller.ex` — handles `{:error, ...}` tuples with proper HTTP status codes
- `priv/repo/migrations/..._create_library.exs` — migration

Use only standard Phoenix/Ecto dependencies.

## Additional interface contract

- Use exactly these module names: router `SoftCrudWeb.Router`, context `SoftCrud.Library` (with `create_folder/1`, `create_document/2`, `soft_delete_folder/1`, and `soft_delete_document/1` returning `{:ok, struct}`), repo `SoftCrud.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `SoftCrudWeb.Router` with `Plug.Test` (no endpoint in front), so every route must be servable by the router pipeline alone.
- Successful creation returns **201** with the created resource JSON.