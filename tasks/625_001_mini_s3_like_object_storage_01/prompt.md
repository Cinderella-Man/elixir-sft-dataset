Write me an Elixir GenServer module called `ObjectStorage` that provides S3-like object storage with bucket semantics, backed by the local filesystem.

I need these functions in the public API:

- `ObjectStorage.start_link(opts)` to start the process. It should accept a `:root_dir` option specifying the base directory for all storage (default `"./object_storage_data"`). It should also accept a `:name` option for process registration.

- `ObjectStorage.create_bucket(server, name)` which creates a new bucket. Return `:ok` if created successfully, or `{:error, :already_exists}` if the bucket already exists. Bucket names must be non-empty strings containing only lowercase alphanumeric characters, hyphens, and dots — return `{:error, :invalid_name}` otherwise.

- `ObjectStorage.delete_bucket(server, name)` which deletes a bucket. Return `:ok` if deleted, `{:error, :not_found}` if the bucket doesn't exist, or `{:error, :not_empty}` if the bucket still contains objects.

- `ObjectStorage.list_buckets(server)` which returns `{:ok, [bucket_name]}` — a sorted list of all bucket names.

- `ObjectStorage.put_object(server, bucket, key, data, content_type \\ "application/octet-stream", metadata \\ %{})` which stores an object. `data` is a binary. `key` is a string like `"images/photo.png"`. `metadata` is a map of arbitrary string key-value pairs. Return `:ok` on success, `{:error, :bucket_not_found}` if the bucket doesn't exist. If the key already exists, overwrite it silently.

- `ObjectStorage.get_object(server, bucket, key)` which retrieves an object. Return `{:ok, %{data: binary, content_type: string, metadata: map, size: integer, last_modified: DateTime.t()}}` on success, `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.

- `ObjectStorage.delete_object(server, bucket, key)` which removes an object. Return `:ok` on success (even if the key didn't exist — idempotent delete), or `{:error, :bucket_not_found}`.

- `ObjectStorage.list_objects(server, bucket, opts \\ [])` which lists object keys in a bucket. Options: `:prefix` (string, default `""`) to filter keys that start with the given prefix, and `:max_keys` (integer, default 1000) to limit results. Return `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}` sorted lexicographically by key, or `{:error, :bucket_not_found}`.

- `ObjectStorage.copy_object(server, src_bucket, src_key, dst_bucket, dst_key)` which copies an object including its content_type and metadata. Return `:ok` on success. Return `{:error, :src_bucket_not_found}`, `{:error, :dst_bucket_not_found}`, or `{:error, :not_found}` (if source key missing) on failure. Copying to the same bucket and key should be a no-op that succeeds.

- `ObjectStorage.start_multipart(server, bucket, key, content_type \\ "application/octet-stream", metadata \\ %{})` which initiates a multipart upload. Return `{:ok, upload_id}` where `upload_id` is a unique string, or `{:error, :bucket_not_found}`.

- `ObjectStorage.upload_part(server, upload_id, part_number, data)` which uploads a single part. `part_number` is a positive integer (1-based). Parts can arrive out of order. Return `:ok` on success, `{:error, :not_found}` if the upload_id is unknown. Uploading the same part_number again should overwrite the previous data for that part.

- `ObjectStorage.complete_multipart(server, upload_id)` which assembles all uploaded parts in part_number order, concatenates their data, and stores the final object. Return `:ok` on success, `{:error, :not_found}` if the upload_id is unknown, or `{:error, :no_parts}` if no parts were uploaded. After completion, the upload_id should be invalidated.

- `ObjectStorage.abort_multipart(server, upload_id)` which cancels the multipart upload and cleans up any stored parts. Return `:ok` on success, `{:error, :not_found}` if unknown.

Store object data on the filesystem under `root_dir`. Use any internal layout you like, but objects must survive a GenServer restart if the same root_dir is reused (bucket and object metadata should be persisted too — you can use `:erlang.term_to_binary` / `from_binary` for metadata files). Multipart upload state is ephemeral and does NOT need to survive restarts.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.