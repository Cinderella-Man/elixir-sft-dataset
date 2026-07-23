# Design brief: `ObjectStorage`

## Problem

We need an S3-like object storage service for Elixir applications: buckets that hold keyed objects, with the object bytes and their descriptive attributes persisted on the local filesystem. The service must also support multipart uploads, so large objects can be assembled from parts that arrive in any order and from more than one upload in flight at a time.

## Constraints

- The module is an Elixir GenServer named `ObjectStorage`.
- Object data is stored on the filesystem under `root_dir`. The internal layout is your choice.
- Only the OTP standard library may be used — no external dependencies.
- The deliverable is the complete module in a single file.
- Multipart upload state is ephemeral and does NOT need to survive restarts.

## Required interface

1. `ObjectStorage.start_link(opts)` — starts the process, returning `{:ok, pid}`. It accepts a `:root_dir` option specifying the base directory for all storage (default `"./object_storage_data"`); create it if it doesn't exist. It also accepts a `:name` option, passed through to `GenServer` for process registration, so the server is reachable both by pid and by that registered name (`Process.whereis(name)` returns the pid, and every API function below accepts the name in place of the pid).

2. `ObjectStorage.create_bucket(server, name)` — creates a new bucket. Returns `:ok` if created successfully, or `{:error, :already_exists}` if the bucket already exists. Bucket names must be non-empty strings containing only lowercase alphanumeric characters, hyphens, and dots — return `{:error, :invalid_name}` otherwise. A non-string argument (atom, integer, …) must also return `{:error, :invalid_name}` rather than crashing, and a rejected name must not create anything on disk.

3. `ObjectStorage.delete_bucket(server, name)` — deletes a bucket. Returns `:ok` if deleted, `{:error, :not_found}` if the bucket doesn't exist, or `{:error, :not_empty}` if the bucket still contains objects.

4. `ObjectStorage.list_buckets(server)` — returns `{:ok, [bucket_name]}`, a sorted list of all bucket names (`{:ok, []}` when there are none).

5. `ObjectStorage.put_object(server, bucket, key, data, content_type \\ "application/octet-stream", metadata \\ %{})` — stores an object. `data` is a binary. `key` is a string like `"images/photo.png"`. `metadata` is a map of arbitrary string key-value pairs. Returns `:ok` on success, `{:error, :bucket_not_found}` if the bucket doesn't exist. If the key already exists, overwrite it silently.

6. `ObjectStorage.get_object(server, bucket, key)` — retrieves an object. Returns `{:ok, %{data: binary, content_type: string, metadata: map, size: integer, last_modified: DateTime.t()}}` on success, where `size` is `byte_size(data)` and `last_modified` is a `%DateTime{}` struct recorded when the object was written. Returns `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.

7. `ObjectStorage.delete_object(server, bucket, key)` — removes an object. Returns `:ok` on success (even if the key didn't exist — idempotent delete), or `{:error, :bucket_not_found}`.

8. `ObjectStorage.list_objects(server, bucket, opts \\ [])` — lists object keys in a bucket. Options: `:prefix` (string, default `""`) to filter keys that start with the given prefix, and `:max_keys` (integer, default 1000) to limit results. Apply them in that order: filter by prefix, sort the surviving keys lexicographically, then take the first `max_keys` of them. Returns `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}`, or `{:error, :bucket_not_found}`. An existing but empty bucket returns `{:ok, []}`.

9. `ObjectStorage.copy_object(server, src_bucket, src_key, dst_bucket, dst_key)` — copies an object including its content_type and metadata, leaving the source in place. Returns `:ok` on success. Failures are checked in this order: `{:error, :src_bucket_not_found}`, `{:error, :dst_bucket_not_found}`, then `{:error, :not_found}` (if source key missing). Copying to the same bucket and key should be a no-op that succeeds and leaves the object unchanged.

10. `ObjectStorage.start_multipart(server, bucket, key, content_type \\ "application/octet-stream", metadata \\ %{})` — initiates a multipart upload. Returns `{:ok, upload_id}` where `upload_id` is a unique string (distinct across concurrent uploads), or `{:error, :bucket_not_found}`. The final object must carry the content_type and metadata given here.

11. `ObjectStorage.upload_part(server, upload_id, part_number, data)` — uploads a single part. `part_number` is a positive integer (1-based). Parts can arrive out of order, and concurrent uploads must not interfere with each other. Returns `:ok` on success, `{:error, :not_found}` if the upload_id is unknown. Uploading the same part_number again should overwrite the previous data for that part.

12. `ObjectStorage.complete_multipart(server, upload_id)` — assembles all uploaded parts in ascending part_number order, concatenates their data, and stores the final object. Returns `:ok` on success, `{:error, :not_found}` if the upload_id is unknown, or `{:error, :no_parts}` if no parts were uploaded. After completion the upload_id must be invalidated — subsequent `upload_part/4`, `complete_multipart/2`, and `abort_multipart/2` calls with it all return `{:error, :not_found}`, and the stored object must not change.

13. `ObjectStorage.abort_multipart(server, upload_id)` — cancels the multipart upload and cleans up any stored parts, so no object is ever created for it. Returns `:ok` on success, `{:error, :not_found}` if unknown. After an abort the upload_id is likewise invalid for `upload_part/4` and `complete_multipart/2`.

## Acceptance criteria

- Every function above behaves exactly as specified, including the stated return shapes, defaults, error atoms, and ordering of checks.
- Objects survive a GenServer restart if the same root_dir is reused: after a `GenServer.stop/1` and a fresh `start_link` on the same root_dir, `list_buckets/1`, `list_objects/3`, and `get_object/3` must return the same buckets, keys, data, content_type, and metadata as before (you can use `:erlang.term_to_binary` / `binary_to_term` for metadata files).
- The complete module is delivered in a single file and uses only the OTP standard library, with no external dependencies.
