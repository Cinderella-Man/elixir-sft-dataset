Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store whose commit history is a **directed acyclic graph (DAG)** — commits may have any number of parents, including two or more for merge commits. This is the key difference from a plain linear-history store: `log` must walk a graph, not a single chain, and there is a `merge_base` operation for finding a common ancestor of two commits.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It should accept a `:name` option for process registration, and must also work when called with `[]` (no name — the process is then addressed by pid). Internal state is an in-memory map of SHA-1 hex digest → stored binary content.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex, 40 characters matching `~r/^[0-9a-f]{40}$/`), persists the raw content keyed by that hash, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not duplicate data.

- `ObjectStore.retrieve(server, hash)` which looks up a hash and returns `{:ok, content}` if found (byte-for-byte what was stored, including embedded null bytes), or `{:error, :not_found}` if the hash does not exist.

- `ObjectStore.commit(server, tree_hash, parents, message, author)` which creates a commit object. `tree_hash` is a SHA-1 string of any already-stored object. `parents` is a **list** of parent commit hashes: use `[]` for a root commit, a single-element list for an ordinary commit, and a two-or-more-element list for a merge commit. `message` and `author` are strings. Build a deterministic text representation containing all fields, store it as an object, and return `{:ok, commit_hash}`. The stored commit object must satisfy `String.printable?/1` and must contain the `tree_hash`, the `author`, and the `message` verbatim as literal substrings, so that `retrieve/2` on a commit hash gives back readable text. Serialization is deterministic: the same `tree_hash`, the same list of `parents` in the same order, the same `message`, and the same `author` always yield the same commit hash. Different parents produce a different hash, and reordering the same parents (`[p1, p2]` vs `[p2, p1]`) produces a different hash too.

- `ObjectStore.log(server, commit_hash)` which returns `{:ok, entries}` where `entries` is a list of maps describing every commit **reachable** from `commit_hash` by transitively following parent links (the starting commit and all of its ancestors). Each map contains `:hash`, `:tree`, `:parents` (the list of parent hashes, in the exact order they were passed to `commit/5`), `:author`, and `:message`. Each reachable commit appears exactly once, even when the graph is a diamond and it is reachable by more than one path. The list is ordered newest-to-oldest: the starting commit is always the first element, and every commit appears **before** all of its ancestors (a reverse-topological ordering). If the starting hash is not found, return `{:error, :not_found}`.

- `ObjectStore.merge_base(server, hash_a, hash_b)` which returns `{:ok, base_hash}` where `base_hash` is a lowest common ancestor of the two commits — a commit that is an ancestor of both `hash_a` and `hash_b` and that is not itself a proper ancestor of any other common ancestor. A commit counts as an ancestor of itself, so `merge_base(s, c, c)` returns `{:ok, c}`, and when one commit is an ancestor of the other that ancestor is the base. If either `hash_a` or `hash_b` is not found, return `{:error, :not_found}`. If the two commits share no common ancestor at all (for example two independent root commits), return `{:error, :no_merge_base}`.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- All stored objects (blobs and commits) live in the same flat hash map — there is no type distinction at the storage layer.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
