Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store, similar in spirit to Git's object model.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It should accept a `:name` option for process registration. Internal state should be an in-memory map of SHA-1 hex digest → stored binary content.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), persists the raw content keyed by that hash, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not duplicate data.

- `ObjectStore.retrieve(server, hash)` which looks up a hash and returns `{:ok, content}` if found, or `{:error, :not_found}` if the hash does not exist in the store.

- `ObjectStore.tree(server, entries)` which takes a list of entry maps, each containing the keys `:name` (a string filename), `:hash` (a SHA-1 hex string referencing an already-stored object), and `:type` (either `:blob` or `:tree`). The function must build a deterministic canonical text representation of the tree by sorting entries by `:name`, serialize it into a single binary string, store that string as an object via the same `store` mechanism, and return `{:ok, tree_hash}`. Two calls with the same entries in any order must produce the same hash.

- `ObjectStore.commit(server, tree_hash, parent_hash, message, author)` which creates a commit object. `tree_hash` is the SHA-1 of a tree object. `parent_hash` is either a SHA-1 string of the parent commit or `nil` for the initial commit. `message` is a string and `author` is a string. Build a deterministic text representation containing all four fields, store it as an object, and return `{:ok, commit_hash}`.

- `ObjectStore.log(server, commit_hash)` which walks the parent chain starting from the given commit hash. It must return `{:ok, entries}` where `entries` is a list of maps, each containing `:hash`, `:message`, `:author`, `:tree`, and `:parent`. The list is ordered from newest to oldest. If the starting hash is not found, return `{:error, :not_found}`. Walking stops when a commit with a `nil` parent is reached.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- Tree serialization must sort entries alphabetically by name before hashing so that entry order in the input list does not affect the resulting hash.
- Commit serialization must use a fixed field order (tree, parent, author, message) so the hash is deterministic.
- All stored objects (blobs, trees, commits) live in the same flat hash map — there is no type distinction at the storage layer.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.