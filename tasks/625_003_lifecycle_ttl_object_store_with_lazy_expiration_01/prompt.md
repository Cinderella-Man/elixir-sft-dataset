# Lifecycle TTL Object Store with Lazy Expiration

Write me an Elixir GenServer module called `TtlObjectStorage` — an S3-like, **in-memory** object store where objects can carry a time-to-live and expire automatically, similar to an S3 lifecycle expiration rule. Expiration is **lazy**: an expired object is treated as absent and is removed the moment it is next touched, and there is also an explicit sweep to reclaim expired objects in bulk. Storage is in memory only and does **not** need to survive a restart.

All TTLs are expressed in **milliseconds** and are measured from the moment of the `put_object` (or `set_ttl`) call. A TTL may also be the atom `:infinity`, meaning the object never expires. An object is considered *expired* once at least its TTL milliseconds have elapsed since it was written or last had its TTL set.

## Public API

- `TtlObjectStorage.start_link(opts)` — start the process, returning `{:ok, pid}`. Accepts a `:name` option for registration (when given, every function below must work when passed that name instead of the pid) and a `:default_ttl_ms` option (a positive integer number of milliseconds, or `:infinity`; default `:infinity`) used for any `put_object` that does not specify its own TTL. `opts` may be empty.

- `TtlObjectStorage.create_bucket(server, name)` — create a bucket. Return `:ok`, or `{:error, :already_exists}`. A valid bucket name is a non-empty string made **entirely** of lowercase letters, digits, hyphens, and dots; anything else — a non-string term such as an atom or integer, the empty string, uppercase letters, spaces, underscores, slashes, or a trailing newline — yields `{:error, :invalid_name}` and creates nothing.

- `TtlObjectStorage.list_buckets(server)` — return `{:ok, [bucket_name]}`, sorted. A fresh server returns `{:ok, []}`.

- `TtlObjectStorage.delete_bucket(server, name)` — delete a bucket, but only if it holds no **live** (unexpired) objects; expired objects are ignored and do not block deletion. Return `:ok`, `{:error, :not_found}` if the bucket does not exist, or `{:error, :not_empty}` if the bucket still contains at least one live object.

- `TtlObjectStorage.put_object(server, bucket, key, data, opts \\ [])` — store an object, overwriting any existing object under the same key (which also resets its TTL). `data` is a binary and may be empty. `opts` may include `:ttl_ms` (a positive integer, or `:infinity`); if omitted, the server's `:default_ttl_ms` applies. Return `:ok`, or `{:error, :bucket_not_found}`.

- `TtlObjectStorage.get_object(server, bucket, key)` — retrieve a live object. Return `{:ok, %{data: binary, size: integer, last_modified: DateTime.t()}}`, where `size` is the byte size of the stored data (`0` for an empty binary). Return `{:error, :bucket_not_found}` if the bucket is missing, or `{:error, :not_found}` if the key does not exist **or** has expired. If the key exists but has expired, this call also removes it (lazy expiration), so a later `purge_expired` no longer counts it.

- `TtlObjectStorage.delete_object(server, bucket, key)` — remove an object. Return `:ok` (idempotent — succeed even if the key does not exist), or `{:error, :bucket_not_found}`.

- `TtlObjectStorage.list_objects(server, bucket)` — return `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}` for the **live** objects only (expired objects are excluded), sorted lexicographically by key using Elixir's default binary ordering (so uppercase keys sort before lowercase ones). An empty bucket returns `{:ok, []}`. Return `{:error, :bucket_not_found}` if the bucket is missing.

- `TtlObjectStorage.set_ttl(server, bucket, key, ttl_ms)` — reset the TTL of an existing live object; `ttl_ms` is a positive integer or `:infinity`, measured from now, and may extend or shorten the object's life. Return `:ok`, `{:error, :bucket_not_found}` if the bucket is missing, or `{:error, :not_found}` if the key does not exist or has already expired.

- `TtlObjectStorage.purge_expired(server)` — sweep every bucket and permanently remove all currently-expired objects. Return `{:ok, count}` where `count` is the total number of objects removed across all buckets (`0` if nothing was expired).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.
