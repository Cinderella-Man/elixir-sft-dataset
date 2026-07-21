Write me an Elixir application composed of a few modules that implements an **asynchronous, status-polled** file upload endpoint with validation, using only `Plug` (no Phoenix). The main entry point is a `Plug.Router` module called `FileUpload.Router` that exposes `POST /api/uploads` and `GET /api/uploads/:id`.

The defining feature of this variation is a **deferred validation pipeline**: the upload is accepted and persisted to disk immediately, the response is HTTP 202 with a `pending` status, and validation runs asynchronously in a separate process. Clients poll the status endpoint to observe the file transition to `valid` or `invalid`. (Only structural failures the server can reject up-front — oversize files and a missing `"file"` field — are handled synchronously; content/type validation is deferred.)

Here's what I need:

**`FileUpload.Router`** — a `Plug.Router` that:

- **POST /api/uploads**: accepts a single file upload under the form field name `"file"`.
  - Enforces a maximum file size of 5MB (`5_242_880` bytes) → HTTP 413 `{"error": "File too large", "max_bytes": 5242880}` (synchronous, before acceptance).
  - If the `"file"` field is missing → HTTP 422 `{"error": "No file provided"}`.
  - Otherwise: create a `pending` record in `FileUpload.Store` (getting a UUID v4 `id`), copy the file to disk as `<id><ext>`, spawn an asynchronous task that validates the persisted file and updates the record's status, and return HTTP **202 Accepted** with `{"id", "original_name", "size", "content_type", "status": "pending", "uploaded_at", "status_url"}` where `status_url` is `"<base_url>/api/uploads/<id>"`.
  - The asynchronous task calls `FileUpload.Validator` on the persisted file. On `:ok` it sets the status to `valid` and stores a `download_url` of `"<base_url>/api/uploads/<id>/download"`. On `{:error, reason}` it sets the status to `invalid` and stores the `reason`.
- **GET /api/uploads/:id**: returns HTTP 200 with the current record as JSON: always `{"id", "original_name", "size", "content_type", "uploaded_at", "status"}` where `status` is one of `"pending"`, `"valid"`, `"invalid"`. When `valid`, also include `"download_url"`. When `invalid`, also include `"error"`. If the id is unknown, HTTP 404 `{"error": "Not found"}`.

The router accepts these options via `plug FileUpload.Router, opts`:
- `:store` — the PID or name of the `FileUpload.Store` GenServer.
- `:upload_dir` — the directory where files are saved.
- `:base_url` — the URL prefix used to build `status_url` and `download_url`.

**`FileUpload.Validator`** — `validate(upload)` on a `%Plug.Upload{}`, returning `:ok` or `{:error, reason}`:
  1. Only `.csv`/`.json` (case-insensitive) → else `{:error, "File type not allowed. Only .csv and .json files are accepted"}`.
  2. CSV: at least two lines OR one comma-containing line, else `{:error, "Invalid CSV: file must contain a header row with multiple columns"}`.
  3. JSON: must `Jason.decode`, else `{:error, "Invalid JSON: " <> description}`.

**`FileUpload.Store`** — a GenServer holding upload records and their status:

- `start_link(opts)` accepts a `:name` option.
- `create(server, metadata)` generates a UUID v4 `:id`, adds `:uploaded_at` (ISO 8601 UTC) and `:status` of `:pending`, stores and returns `{:ok, record}`.
- `update_status(server, id, status, extra)` merges `extra` (a map) into the record and sets its `:status`; returns `:ok`. For an unknown `id` it returns `{:error, :not_found}` — it must not crash and must not report `:ok`.
- `get(server, id)` → `{:ok, record}` | `{:error, :not_found}`.
- `list(server)` → all records.

Use `Jason` for JSON, `:crypto` for the UUID, and a plain process (`Task.start`) for the async validation so the request returns immediately. Only standard OTP plus `Plug` and `Jason`. One file, three modules, each with a `@moduledoc`.