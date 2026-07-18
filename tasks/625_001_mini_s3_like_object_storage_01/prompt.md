Write me an Elixir GenServer module called `ObjectStorage` that provides S3-like object storage with bucket semantics, backed by the local filesystem.

I need these functions in the public API:

- `ObjectStorage.start_link(opts)` to start the process, returning `{:ok, pid}`. It should accept a `:root_dir` option specifying the base directory for all storage (default `"./object_storage_data"`) — create it if it doesn't exist. It should also accept a `:name` option, passed through to `GenServer` for process registration, so the server is reachable both by pid and by that registered name (`Process.whereis(name)` returns the pid, and every API function below accepts the name in place of the pid).

- `ObjectStorage.create_bucket(server, name)` which creates a new bucket. Return `:ok` if created successfully, or `{:error, :already_exists}` if the bucket already exists. Bucket names must be non-empty strings containing only lowercase alphanumeric characters, hyphens, and dots — return `{:error, :invalid_name}` otherwise. A non-string argument (atom, integer, …) must also return `{:error, :invalid_name}` rather than crashing, and a rejected name must not create anything on disk.

- `ObjectStorage.delete_bucket(server, name)` which deletes a bucket. Return `:ok` if deleted, `{:error, :not_found}` if the bucket doesn't exist, or `{:error, :not_empty}` if the bucket still contains objects.

- `ObjectStorage.list_buckets(server)` which returns `{:ok, [bucket_name]}` — a sorted list of all bucket names (`{:ok, []}` when there are none).

- `ObjectStorage.put_object(server, bucket, key, data, content_type \\ "application/octet-stream", metadata \\ %{})` which stores an object. `data` is a binary. `key` is a string like `"images/photo.png"`. `metadata` is a map of arbitrary string key-value pairs. Return `:ok` on success, `{:error, :bucket_not_found}` if the bucket doesn't exist. If the key already exists, overwrite it silently.

- `ObjectStorage.get_object(server, bucket, key)` which retrieves an object. Return `{:ok, %{data: binary, content_type: string, metadata: map, size: integer, last_modified: DateTime.t()}}` on success, where `size` is `byte_size(data)` and `last_modified` is a `%DateTime{}` struct recorded when the object was written. Return `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.

- `ObjectStorage.delete_object(server, bucket, key)` which removes an object. Return `:ok` on success (even if the key didn't exist — idempotent delete), or `{:error, :bucket_not_found}`.

- `ObjectStorage.list_objects(server, bucket, opts \\ [])` which lists object keys in a bucket. Options: `:prefix` (string, default `""`) to filter keys that start with the given prefix, and `:max_keys` (integer, default 1000) to limit results. Apply them in that order: filter by prefix, sort the surviving keys lexicographically, then take the first `max_keys` of them. Return `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}`, or `{:error, :bucket_not_found}`. An existing but empty bucket returns `{:ok, []}`.

- `ObjectStorage.copy_object(server, src_bucket, src_key, dst_bucket, dst_key)` which copies an object including its content_type and metadata, leaving the source in place. Return `:ok` on success. Check failures in this order: `{:error, :src_bucket_not_found}`, `{:error, :dst_bucket_not_found}`, then `{:error, :not_found}` (if source key missing). Copying to the same bucket and key should be a no-op that succeeds and leaves the object unchanged.

- `ObjectStorage.start_multipart(server, bucket, key, content_type \\ "application/octet-stream", metadata \\ %{})` which initiates a multipart upload. Return `{:ok, upload_id}` where `upload_id` is a unique string (distinct across concurrent uploads), or `{:error, :bucket_not_found}`. The final object must carry the content_type and metadata given here.

- `ObjectStorage.upload_part(server, upload_id, part_number, data)` which uploads a single part. `part_number` is a positive integer (1-based). Parts can arrive out of order, and concurrent uploads must not interfere with each other. Return `:ok` on success, `{:error, :not_found}` if the upload_id is unknown. Uploading the same part_number again should overwrite the previous data for that part.

- `ObjectStorage.complete_multipart(server, upload_id)` which assembles all uploaded parts in ascending part_number order, concatenates their data, and stores the final object. Return `:ok` on success, `{:error, :not_found}` if the upload_id is unknown, or `{:error, :no_parts}` if no parts were uploaded. After completion the upload_id must be invalidated — subsequent `upload_part/4`, `complete_multipart/2`, and `abort_multipart/2` calls with it all return `{:error, :not_found}`, and the stored object must not change.

- `ObjectStorage.abort_multipart(server, upload_id)` which cancels the multipart upload and cleans up any stored parts, so no object is ever created for it. Return `:ok` on success, `{:error, :not_found}` if unknown. After an abort the upload_id is likewise invalid for `upload_part/4` and `complete_multipart/2`.

Store object data on the filesystem under `root_dir`. Use any internal layout you like, but objects must survive a GenServer restart if the same root_dir is reused — after a `GenServer.stop/1` and a fresh `start_link` on the same root_dir, `list_buckets/1`, `list_objects/3`, and `get_object/3` must return the same buckets, keys, data, content_type, and metadata as before (you can use `:erlang.term_to_binary` / `binary_to_term` for metadata files). Multipart upload state is ephemeral and does NOT need to survive restarts.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
