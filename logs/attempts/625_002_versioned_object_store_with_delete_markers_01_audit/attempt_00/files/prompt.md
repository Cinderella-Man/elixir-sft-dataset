# Versioned Object Store with Delete Markers

Write me an Elixir GenServer module called `VersionedObjectStorage` that provides an S3-like object store where **every write keeps history** — like S3 bucket versioning. It is backed by the local filesystem so history survives a restart.

## Public API

- `VersionedObjectStorage.start_link(opts)` — start the process. Accepts a `:root_dir` option (base directory for all storage, default `"./versioned_object_storage_data"`) and a `:name` option for process registration.

- `VersionedObjectStorage.create_bucket(server, name)` — create a bucket. Return `:ok`, or `{:error, :already_exists}` if it already exists. Bucket names must be non-empty strings containing only lowercase alphanumeric characters, hyphens, and dots — otherwise return `{:error, :invalid_name}`.

- `VersionedObjectStorage.list_buckets(server)` — return `{:ok, [bucket_name]}`, a sorted list of bucket names.

- `VersionedObjectStorage.put_object(server, bucket, key, data, metadata \\ %{})` — store a new **version** of an object. `data` is a binary; `metadata` is a map of arbitrary key-value pairs. Each call creates a brand-new version and never destroys earlier versions. Return `{:ok, version_id}` where `version_id` is a unique binary string, or `{:error, :bucket_not_found}` if the bucket does not exist.

- `VersionedObjectStorage.get_object(server, bucket, key)` — retrieve the **latest** version of a key. Return `{:ok, %{data: binary, metadata: map, size: integer, version_id: string, last_modified: DateTime.t()}}`. Return `{:error, :bucket_not_found}` if the bucket is missing, or `{:error, :not_found}` if the key has no versions **or** its latest version is a delete marker (see below).

- `VersionedObjectStorage.get_object_version(server, bucket, key, version_id)` — retrieve one specific version by its id. Return `{:ok, %{data: binary, metadata: map, size: integer, version_id: string, is_delete_marker: boolean, last_modified: DateTime.t()}}`. For a delete marker, `data` is the empty binary `""` and `is_delete_marker` is `true`. Return `{:error, :bucket_not_found}` or `{:error, :not_found}` (unknown version) on failure.

- `VersionedObjectStorage.delete_object(server, bucket, key)` — perform a **soft delete** by appending a new *delete marker* version. This hides the object from `get_object` and `list_objects` but preserves all earlier versions. Return `{:ok, version_id}` (the delete marker's version id), or `{:error, :bucket_not_found}`.

- `VersionedObjectStorage.list_versions(server, bucket, key)` — return `{:ok, [%{version_id: string, is_delete_marker: boolean, size: integer, last_modified: DateTime.t()}]}` ordered **newest first** (most recently written version at the head). Return `{:error, :bucket_not_found}`. If the key has no versions, return `{:ok, []}`.

- `VersionedObjectStorage.delete_version(server, bucket, key, version_id)` — **permanently** remove one specific version by id. Return `:ok` (idempotent — succeed even if that version does not exist), or `{:error, :bucket_not_found}`. Permanently deleting the latest delete marker effectively *restores* the object: whatever version now has the highest recency becomes the latest again.

- `VersionedObjectStorage.list_objects(server, bucket)` — return `{:ok, [%{key: string, size: integer, version_id: string, last_modified: DateTime.t()}]}` describing the **current** state of the bucket: only keys whose latest version is a real object (not a delete marker), sorted lexicographically by key. Return `{:error, :bucket_not_found}`.

## Persistence

Store everything under `root_dir`. Buckets, all object versions (data + metadata), and delete markers must survive a GenServer restart if the same `root_dir` is reused. You may use any internal layout and `:erlang.term_to_binary` / `:erlang.binary_to_term` for serialization.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.