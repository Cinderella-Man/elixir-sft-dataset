# Specification: `ObjectStore` — Content-Addressable Object Store with Mutable Branch References and Reachability GC

## Overview

This document specifies an Elixir GenServer module named `ObjectStore` that implements a content-addressable object store with a layer of **mutable named branch references** on top of the immutable objects, plus **reachability-based garbage collection** — like Git's refs (branches) and `git gc`. Objects are immutable and content-addressed; branches are mutable pointers to commit hashes, updated with an atomic compare-and-swap, and unreferenced objects can be swept away.

The deliverable is the complete module in a single file. Only the OTP standard library may be used; no external dependencies.

## API

The following functions constitute the public API.

### `ObjectStore.start_link(opts)`

Starts the process. It accepts an optional `:name` option for process registration; it must also work when called with an empty list, e.g. `ObjectStore.start_link([])`. When `:name` is given, all API functions must work when passed that name in place of a pid. Internal state holds an in-memory map of SHA-1 hex digest → stored binary content, plus a separate mapping of branch name → commit hash.

### `ObjectStore.store(server, content)`

Computes the SHA-1 (lowercase hex) of `content`, persists the raw bytes keyed by that hash, and returns `{:ok, hash}`. `content` is an arbitrary binary and may contain null bytes; it is stored and returned byte-for-byte. The operation is idempotent — the same content yields the same hash and is stored only once, so storing it twice leaves exactly one object.

### `ObjectStore.retrieve(server, hash)`

Returns `{:ok, content}` with the exact bytes that were stored, or `{:error, :not_found}`.

### `ObjectStore.commit(server, tree_hash, parent_hash, message, author)`

Creates a commit object. `tree_hash` is a SHA-1 string of any stored object. `parent_hash` is either a SHA-1 string of the parent commit or `nil` for a root commit. `message` and `author` are strings. The implementation builds a deterministic text representation (same arguments always give the same hash; changing the message or the author alone must change the hash), stores it as a normal object — retrievable via `retrieve/2`, with a hash equal to the SHA-1 of its own serialized bytes — and returns `{:ok, commit_hash}`.

### `ObjectStore.create_branch(server, name, commit_hash)`

Creates a branch named `name` (a string) pointing at `commit_hash`. Returns `{:ok, name}`. If a branch with that name already exists, it returns `{:error, :exists}`. If `commit_hash` is not an existing stored object, it returns `{:error, :not_found}`. Any stored object is an acceptable target — a branch may point at a plain blob, not just a commit.

### `ObjectStore.branch_head(server, name)`

Returns `{:ok, commit_hash}` for the commit a branch points at, or `{:error, :no_branch}` if no such branch exists.

### `ObjectStore.update_branch(server, name, expected_hash, new_hash)`

Performs an atomic compare-and-swap: it moves branch `name` to `new_hash` **only if** the branch currently points at `expected_hash`. On success it returns `{:ok, new_hash}` (including the no-op case where `new_hash` equals the current head). If the branch does not exist, it returns `{:error, :no_branch}`. If `new_hash` is not an existing stored object, it returns `{:error, :not_found}`. If the branch exists but does not currently point at `expected_hash`, it returns `{:error, :conflict}` and leaves the branch unchanged.

### `ObjectStore.delete_branch(server, name)`

Removes a branch and returns `:ok`, or `{:error, :no_branch}` if it does not exist.

### `ObjectStore.list_branches(server)`

Returns a map of branch name → commit hash for all branches — `%{}` for a fresh store, and reflecting creations, compare-and-swap moves, and deletions.

### `ObjectStore.gc(server)`

Garbage-collects unreferenced objects and returns `{:ok, removed_count}`, the number of objects deleted (`{:ok, 0}` when nothing is unreachable, so repeated calls converge). An object is **reachable** if any of the following holds: (a) it is the object a branch points at directly (commit or blob); (b) it is an ancestor commit found by following `parent` links transitively — through arbitrarily many hops — from any branch head; or (c) it is the tree object referenced (via `tree_hash`) by any reachable commit, including trees of ancestor commits. Every stored object that is not reachable is deleted.

## Edge cases

- `content` passed to `store/2` may contain null bytes; the bytes round-trip unchanged.
- Storing identical content twice results in exactly one stored object.
- `retrieve/2` on an unknown hash yields `{:error, :not_found}`.
- `parent_hash` of `nil` in `commit/5` denotes a root commit.
- Two commits differing only in `message`, or only in `author`, must hash differently.
- `create_branch/3` on an existing name yields `{:error, :exists}`; on a hash that is not an existing stored object it yields `{:error, :not_found}`.
- A branch may point at a plain blob rather than a commit.
- `branch_head/2` and `delete_branch/2` on a missing branch yield `{:error, :no_branch}`.
- `update_branch/4` where `new_hash` equals the current head still succeeds with `{:ok, new_hash}`.
- `update_branch/4` on a missing branch yields `{:error, :no_branch}`; with a `new_hash` that is not an existing stored object it yields `{:error, :not_found}`; on a head mismatch it yields `{:error, :conflict}` with the branch left unchanged.
- `list_branches/1` returns `%{}` for a fresh store.
- With no branches at all, `gc/1` sweeps everything.
- A loose blob that is not referenced as some reachable commit's tree is unreachable and will be removed.
- Repeated `gc/1` calls converge, returning `{:ok, 0}` once nothing is unreachable.

## Implementation requirements

- SHA-1 hashing uses `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)`.
- Commit serialization must be deterministic and include the tree, parent (using the literal `nil` when there is no parent), author, and message so that ancestry and tree references can be recovered when computing reachability.
- All stored objects (blobs and commits) live in the same flat hash map; branches live in a separate map.
