Write me an Elixir application composed of a few modules that implements a **content-addressable, deduplicating** file upload endpoint with validation, using only `Plug` (no Phoenix). The main entry point is a `Plug.Router` module called `FileUpload.Router` that exposes `POST /api/uploads`.

The defining feature of this variation is **content-addressable storage with deduplication**: a file's identity is the SHA-256 hash of its bytes. Uploading the same content twice (even under different filenames) must NOT create a second stored record or a second file on disk — the second request is recognized as a duplicate and returns the existing metadata.

Here's what I need:

**`FileUpload.Router`** — a `Plug.Router` that:

- Accepts a single file upload under the form field name `"file"`.
- Enforces a maximum file size of 5MB (`5_242_880` bytes). If a request exceeds this, return HTTP 413 with JSON body `{"error": "File too large", "max_bytes": 5242880}`.
- Delegates validation to `FileUpload.Validator` and storage to `FileUpload.Store`.
- Computes the SHA-256 hash of the file's contents (lowercase hex, 64 chars) and uses it as the file `id`.
- On a **new** upload (hash not seen before), returns HTTP 201 with JSON metadata: `{"id", "original_name", "size", "content_type", "uploaded_at", "upload_count", "deduplicated", "download_url"}` where `deduplicated` is `false` and `upload_count` is `1`. The file is written to disk once, named `<hash><ext>`.
- On a **duplicate** upload (hash already stored), returns HTTP 200 with the SAME metadata, `deduplicated` set to `true`, and `upload_count` incremented. NO new disk file is written.
- On validation failure, returns HTTP 422 with JSON body `{"error": "<descriptive message>"}`.
- If the `"file"` field is missing, return HTTP 422 with `{"error": "No file provided"}`.

The router must accept these options at init time via `plug FileUpload.Router, opts`:
- `:store` — the PID or name of the `FileUpload.Store` GenServer.
- `:upload_dir` — the directory path where files are saved to disk.
- `:base_url` — the URL prefix for generating download URLs (e.g. `"http://localhost:4000"`). The download URL is `"<base_url>/api/uploads/<hash>"`.

**`FileUpload.Validator`** — a module with a single public function `validate(upload)` where `upload` is a `%Plug.Upload{}` struct. It returns `:ok` or `{:error, reason_string}`:
  1. **File type**: only `.csv` and `.json` extensions are allowed (check the `filename` field, case-insensitive). If not, return `{:error, "File type not allowed. Only .csv and .json files are accepted"}`.
  2. **Content validity for CSV**: read the file, and confirm it has at least two lines OR at least one line containing a comma. Otherwise return `{:error, "Invalid CSV: file must contain a header row with multiple columns"}`.
  3. **Content validity for JSON**: read the file and attempt `Jason.decode`. If it fails, return `{:error, "Invalid JSON: " <> description}`.

**`FileUpload.Store`** — a GenServer keyed by content hash:

- `start_link(opts)` accepts a `:name` option for process registration.
- `save(server, hash, metadata)` stores metadata under `hash`. If the hash is new, it adds `:id` (= hash), an `:uploaded_at` ISO 8601 UTC timestamp, and `:upload_count` of `1`, returning `{:ok, :created, record}`. If the hash already exists, it increments `:upload_count` and returns `{:ok, :exists, record}` (preserving the original `:id`, `:original_name`, and `:uploaded_at`).
- `get(server, id)` returns `{:ok, metadata}` or `{:error, :not_found}`.
- `list(server)` returns all stored metadata as a list.

Use `Jason` for JSON, `:crypto`/`Base` for hashing. Only standard OTP plus `Plug` and `Jason`. Keep everything in a single file, clearly separated into the three modules, each with a `@moduledoc`.