I need you to write me an Elixir GenServer module called `ObjectStore` — a content-addressable object store, but one that actually **persists objects to disk** as compressed "loose object" files, the way Git does under `.git/objects`, and that **verifies integrity on read**. The key thing for me is that the store keeps no in-memory copy of object contents — every read and every write goes to the filesystem. That way a second process pointed at the same directory sees the same objects, and objects survive process restarts.

Here's the public API I'm after:

`ObjectStore.start_link(opts)` starts the process and returns `{:ok, pid}`. It should accept an optional `:name` option for process registration — when it's given, register the process under that atom, so `Process.whereis(name)` returns the pid and the name can be handed to every other function as `server`. It also takes a **required** `:dir` option naming the directory the objects live in. Please fetch `:dir` with `Keyword.fetch!/2` so that calling `start_link/1` without it raises `KeyError`. If the directory doesn't exist yet, create it on startup, including any missing parent directories.

`ObjectStore.store(server, content)` takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), writes the object to disk, and returns `{:ok, hash}`. Storing the same content twice has to be idempotent — same hash back, and no rewriting the file if it's already there (I care that the existing file's mtime is left untouched). Empty content and content with arbitrary bytes, null bytes included, must round-trip.

`ObjectStore.retrieve(server, hash)` reads the object file for `hash`, decompresses it, and returns `{:ok, content}` where `content` is the exact binary that went in. If there's no file for that hash, return `{:error, :not_found}`. If the file exists but won't decompress, or the SHA-1 of the decompressed bytes doesn't equal the requested hash, return `{:error, :corrupt}` — and please catch the decompression failure rather than letting it crash the process.

`ObjectStore.has_object?(server, hash)` returns `true` if an object file exists for `hash`, `false` otherwise.

`ObjectStore.list_objects(server)` returns a sorted list of the SHA-1 hex hashes of every object currently on disk, or `[]` when the store is empty. Since it scans the directory on each call, it needs to pick up objects written by another process pointed at the same directory.

The on-disk layout is a fixed contract, so don't improvise here: the file path for an object with hash `H` is `<dir>/<first two characters of H>/<remaining 38 characters of H>` — the object goes in a two-character fan-out subdirectory named by the first two hex characters, in a file named by the remaining 38. The file contents are the **zlib-compressed** raw object bytes; compress with `:zlib.compress/1` and decompress with `:zlib.uncompress/1`.

Two implementation points I want followed: use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for the SHA-1 hashing, and keep all object contents on disk — no in-memory content map in the process state.

Give me the complete module in a single file, using only the OTP standard library, no external dependencies.
