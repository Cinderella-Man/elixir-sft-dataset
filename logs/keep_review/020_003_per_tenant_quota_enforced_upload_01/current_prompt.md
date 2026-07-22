Write me an Elixir application composed of a few modules that implements a **multi-tenant, quota-enforced** file upload endpoint with validation, using only `Plug` (no Phoenix). The main entry point is a `Plug.Router` module called `FileUpload.Router` that exposes `POST /api/uploads` and `DELETE /api/uploads/:id`.

The defining feature of this variation is a **per-account byte quota** with all-or-nothing, atomic failure semantics: every request is attributed to an account (via the `x-account-id` request header), each account has a fixed total-bytes budget configured on the `FileUpload.Store`, and an upload that would push an account over its budget is rejected with HTTP 507 **without consuming any quota or writing anything**. Deleting a file releases its bytes back to the owning account's budget.

Here's what I need:

**`FileUpload.Router`** — a `Plug.Router` that:

- Reads the account id from the `x-account-id` request header. If it is missing or empty, return HTTP 400 with `{"error": "Missing account"}` (for both POST and DELETE).
- **POST /api/uploads**: accepts a single file upload under the form field name `"file"`.
  - Enforces a maximum single-file size of 5MB (`5_242_880` bytes) → HTTP 413 `{"error": "File too large", "max_bytes": 5242880}`.
  - Delegates validation to `FileUpload.Validator` (422 on failure with `{"error": "<message>"}`).
  - If the `"file"` field is missing → HTTP 422 `{"error": "No file provided"}`.
  - Asks `FileUpload.Store` to reserve quota and save. On success (HTTP 201): `{"id", "original_name", "size", "content_type", "uploaded_at", "account_id", "used_bytes", "quota_bytes", "download_url"}` where `used_bytes` is the account's total AFTER this upload. The file is written to disk as `<id><ext>`.
  - On quota rejection: HTTP 507 with `{"error": "Quota exceeded", "quota_bytes": Q, "used_bytes": U, "requested_bytes": S}` where `U` is the account's usage BEFORE the rejected request (unchanged). No file is written.
- **DELETE /api/uploads/:id**: only the owning account may delete.
  - Success → HTTP 200 `{"id", "freed_bytes", "used_bytes"}` (usage after release), and the disk file is removed.
  - If the file exists but belongs to another account → HTTP 403 `{"error": "Forbidden"}`.
  - If the file does not exist → HTTP 404 `{"error": "Not found"}`.

The router accepts these options via `plug FileUpload.Router, opts`:
- `:store` — the PID or name of the `FileUpload.Store` GenServer.
- `:upload_dir` — the directory where files are saved.
- `:base_url` — the URL prefix for download URLs (`"<base_url>/api/uploads/<id>"`).

**`FileUpload.Validator`** — `validate(upload)` on a `%Plug.Upload{}`, returning `:ok` or `{:error, reason}`:
  1. Only `.csv`/`.json` (case-insensitive) → else `{:error, "File type not allowed. Only .csv and .json files are accepted"}`.
  2. CSV: at least two lines OR one comma-containing line, else `{:error, "Invalid CSV: file must contain a header row with multiple columns"}`.
  3. JSON: must `Jason.decode`, else `{:error, "Invalid JSON: " <> description}`.

**`FileUpload.Store`** — a GenServer that tracks per-account usage:

- `start_link(opts)` accepts `:name` and `:quota_bytes` (the per-account budget; default `10_000_000`).
- `save(server, account, metadata)` where `metadata` has `:size`. Atomically: if `used(account) + size > quota` return `{:error, :quota_exceeded, %{quota: q, used: used, requested: size}}` (no state change). Otherwise generate a UUID v4 `:id`, add `:uploaded_at` (ISO 8601 UTC) and `:account`, store it, add `size` to the account's usage, and return `{:ok, record, %{quota: q, used: new_used}}`.
- `delete(server, account, id)` returns `{:ok, %{record: record, freed: size, used: new_used}}` (releasing quota, decrementing usage), `{:error, :forbidden}` if `id` belongs to a different account, or `{:error, :not_found}`.
- `get(server, id)` → `{:ok, metadata}` | `{:error, :not_found}`.
- `usage(server, account)` → the account's current used bytes (0 if unknown).
- `list(server)` → all stored metadata.

Use `Jason` for JSON, `:crypto` for the UUID. Only standard OTP plus `Plug` and `Jason`. One file, three modules, each with a `@moduledoc`.