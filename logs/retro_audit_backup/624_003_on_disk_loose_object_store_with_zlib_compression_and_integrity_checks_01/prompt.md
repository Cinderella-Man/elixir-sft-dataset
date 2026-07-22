Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store which **persists objects to disk** as compressed "loose object" files (like Git's `.git/objects` directory) and **verifies integrity on read**. The store keeps no in-memory copy of object contents — every read and write goes to the filesystem — so a second process pointed at the same directory sees the same objects, and objects survive process restarts.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It accepts an optional `:name` option for process registration and a **required** `:dir` option giving the directory in which objects are stored. If the directory does not exist it must be created on startup.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), writes the object to disk, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not rewrite the file if it already exists.

- `ObjectStore.retrieve(server, hash)` which reads the object file for `hash`, decompresses it, and returns `{:ok, content}`. If no file exists for that hash it returns `{:error, :not_found}`. If the file exists but cannot be decompressed, or the SHA-1 of the decompressed bytes does not equal the requested hash, it returns `{:error, :corrupt}`.

- `ObjectStore.has_object?(server, hash)` which returns `true` if an object file exists for `hash`, `false` otherwise.

- `ObjectStore.list_objects(server)` which returns a sorted list of the SHA-1 hex hashes of every object currently present on disk.

On-disk layout (this is a fixed contract):
- The file path for an object with hash `H` is `<dir>/<first two characters of H>/<remaining 38 characters of H>`. That is, the object is stored in a two-character fan-out subdirectory named by the first two hex characters, in a file named by the remaining 38.
- The file contents are the **zlib-compressed** raw object bytes. Compress with `:zlib.compress/1` and decompress with `:zlib.uncompress/1`.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- All object contents live on disk; there is no in-memory content map in the process state.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.