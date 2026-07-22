# Conditional-Write Object Store with ETags

Write me an Elixir GenServer module called `ConditionalObjectStorage` — an S3-like, **in-memory** object store that supports **optimistic concurrency** through conditional requests, exactly like S3's `If-Match` / `If-None-Match` preconditions. Every stored object carries an **ETag**, defined as the **lowercase hex-encoded SHA-256 of the object's data** (so identical data always yields the same ETag, and different data yields a different ETag).

## Public API

- `ConditionalObjectStorage.start_link(opts)` — start the process. Accepts a `:name` option for registration.

- `ConditionalObjectStorage.create_bucket(server, name)` — create a bucket. Return `:ok`, or `{:error, :already_exists}`. Bucket names must be non-empty strings of lowercase alphanumeric characters, hyphens, and dots — otherwise `{:error, :invalid_name}`.

- `ConditionalObjectStorage.list_buckets(server)` — return `{:ok, [bucket_name]}`, sorted.

- `ConditionalObjectStorage.put_object(server, bucket, key, data, opts \\ [])` — store an object. `data` is a binary. `opts` may contain **at most one** precondition:
  - `:if_none_match` with the value `"*"` — the write succeeds only if the key does **not** currently exist (a create-only / no-overwrite write). If the key already exists, return `{:error, :precondition_failed}` and leave the stored object unchanged.
  - `:if_match` with an ETag string — the write succeeds only if the key currently exists **and** its ETag equals the given value (a compare-and-swap). If the key is absent or its ETag differs, return `{:error, :precondition_failed}` and leave any stored object unchanged.
  - With no precondition, the write unconditionally creates or overwrites.

  On success, return `{:ok, etag}` where `etag` is the new object's ETag. Return `{:error, :bucket_not_found}` if the bucket does not exist (preconditions are only evaluated for an existing bucket).

- `ConditionalObjectStorage.get_object(server, bucket, key, opts \\ [])` — retrieve an object. Return `{:ok, %{data: binary, etag: string, size: integer, last_modified: DateTime.t()}}`. `opts` may contain `:if_none_match` with an ETag string: if the object's current ETag equals that value, return `{:error, :not_modified}` instead of the body (a cache-revalidation read). Return `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.

- `ConditionalObjectStorage.delete_object(server, bucket, key, opts \\ [])` — remove an object. With no precondition this is an idempotent delete: return `:ok` even if the key does not exist. `opts` may contain `:if_match` with an ETag string — the delete then succeeds only if the key exists and its ETag matches; otherwise return `{:error, :precondition_failed}` and leave the object in place. Return `{:error, :bucket_not_found}` if the bucket is missing.

- `ConditionalObjectStorage.list_objects(server, bucket)` — return `{:ok, [%{key: string, etag: string, size: integer, last_modified: DateTime.t()}]}` sorted lexicographically by key, or `{:error, :bucket_not_found}`.

Storage is in memory only and does not need to survive a restart. Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.