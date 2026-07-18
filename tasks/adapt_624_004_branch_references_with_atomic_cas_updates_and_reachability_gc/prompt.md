# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store implemented as a GenServer,
  similar in spirit to Git's object model.

  All objects (blobs, trees, commits) are stored in a single flat
  map keyed by their SHA-1 hex digest. Storing identical content
  is idempotent — it always returns the same hash.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the ObjectStore process.

  ## Options
    * `:name` — optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{}, server_opts)
  end

  @doc """
  Stores an arbitrary binary and returns its SHA-1 hex digest.

  Idempotent — storing the same content twice returns the same hash
  without duplicating data.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, String.t()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves previously-stored content by its SHA-1 hex digest.

  Returns `{:ok, content}` or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), String.t()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates a tree object from a list of entry maps.

  Each entry must contain:
    * `:name`  — filename (string)
    * `:hash`  — SHA-1 hex of an already-stored object
    * `:type`  — `:blob` or `:tree`

  Entries are sorted alphabetically by `:name` before serialization,
  so the resulting hash is independent of input order.
  """
  @spec tree(GenServer.server(), [map()]) :: {:ok, String.t()}
  def tree(server, entries) when is_list(entries) do
    GenServer.call(server, {:tree, entries})
  end

  @doc """
  Creates a commit object.

  * `tree_hash`   — SHA-1 of the tree object for this commit
  * `parent_hash` — SHA-1 of the parent commit, or `nil` for the initial commit
  * `message`     — commit message (string)
  * `author`      — author name (string)
  """
  @spec commit(GenServer.server(), String.t(), String.t() | nil, String.t(), String.t()) ::
          {:ok, String.t()}
  def commit(server, tree_hash, parent_hash, message, author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end

  @doc """
  Walks the parent chain starting from `commit_hash` and returns a list
  of commit maps ordered from newest to oldest.

  Each map contains `:hash`, `:message`, `:author`, `:tree`, and `:parent`.

  Returns `{:error, :not_found}` if the starting hash does not exist.
  """
  @spec log(GenServer.server(), String.t()) ::
          {:ok, [map()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    {hash, state} = do_store(state, content)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:tree, entries}, _from, state) do
    serialized =
      entries
      |> Enum.sort_by(& &1.name)
      |> Enum.map_join("\n", fn entry ->
        type_str = Atom.to_string(entry.type)
        "#{type_str} #{entry.hash} #{entry.name}"
      end)

    {hash, state} = do_store(state, serialized)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:commit, tree_hash, parent_hash, message, author}, _from, state) do
    parent_str = parent_hash || "nil"

    serialized =
      "tree #{tree_hash}\nparent #{parent_str}\nauthor #{author}\nmessage #{message}"

    {hash, state} = do_store(state, serialized)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:log, commit_hash}, _from, state) do
    case walk_log(state, commit_hash, []) do
      {:ok, entries} -> {:reply, {:ok, entries}, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp do_store(state, content) do
    hash = sha1(content)
    {hash, Map.put_new(state, hash, content)}
  end

  defp sha1(content) do
    :crypto.hash(:sha, content)
    |> Base.encode16(case: :lower)
  end

  defp walk_log(_state, nil, acc), do: {:ok, Enum.reverse(acc)}

  defp walk_log(state, hash, acc) do
    case Map.fetch(state, hash) do
      :error when acc == [] ->
        {:error, :not_found}

      :error ->
        # Dangling parent reference — stop gracefully.
        {:ok, Enum.reverse(acc)}

      {:ok, content} ->
        parsed = parse_commit(content)

        entry = %{
          hash: hash,
          tree: parsed.tree,
          parent: parsed.parent,
          author: parsed.author,
          message: parsed.message
        }

        walk_log(state, parsed.parent, [entry | acc])
    end
  end

  defp parse_commit(content) do
    lines = String.split(content, "\n", parts: 4)

    raw_parent = strip_prefix(Enum.at(lines, 1), "parent ")
    parent = if raw_parent == "nil", do: nil, else: raw_parent

    %{
      tree: strip_prefix(Enum.at(lines, 0), "tree "),
      parent: parent,
      author: strip_prefix(Enum.at(lines, 2), "author "),
      message: strip_prefix(Enum.at(lines, 3), "message ")
    }
  end

  defp strip_prefix(str, prefix) do
    String.replace_prefix(str, prefix, "")
  end
end
```

## New specification

Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store with a layer of **mutable named branch references** on top of the immutable objects, plus **reachability-based garbage collection** — like Git's refs (branches) and `git gc`. Objects are immutable and content-addressed; branches are mutable pointers to commit hashes, updated with an atomic compare-and-swap, and unreferenced objects can be swept away.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It accepts an optional `:name` option for process registration; it must also work when called with an empty list, e.g. `ObjectStore.start_link([])`. When `:name` is given, all API functions must work when passed that name in place of a pid. Internal state holds an in-memory map of SHA-1 hex digest → stored binary content, plus a separate mapping of branch name → commit hash.

- `ObjectStore.store(server, content)` which computes the SHA-1 (lowercase hex) of `content`, persists the raw bytes keyed by that hash, and returns `{:ok, hash}`. `content` is an arbitrary binary and may contain null bytes; store and return it byte-for-byte. Idempotent — the same content yields the same hash and is stored only once, so storing it twice leaves exactly one object.

- `ObjectStore.retrieve(server, hash)` returns `{:ok, content}` with the exact bytes that were stored, or `{:error, :not_found}`.

- `ObjectStore.commit(server, tree_hash, parent_hash, message, author)` creates a commit object. `tree_hash` is a SHA-1 string of any stored object. `parent_hash` is either a SHA-1 string of the parent commit or `nil` for a root commit. `message` and `author` are strings. Build a deterministic text representation (same arguments always give the same hash; changing the message or the author alone must change the hash), store it as a normal object — retrievable via `retrieve/2`, with a hash equal to the SHA-1 of its own serialized bytes — and return `{:ok, commit_hash}`.

- `ObjectStore.create_branch(server, name, commit_hash)` creates a branch named `name` (a string) pointing at `commit_hash`. Returns `{:ok, name}`. If a branch with that name already exists, return `{:error, :exists}`. If `commit_hash` is not an existing stored object, return `{:error, :not_found}`. Any stored object is an acceptable target — a branch may point at a plain blob, not just a commit.

- `ObjectStore.branch_head(server, name)` returns `{:ok, commit_hash}` for the commit a branch points at, or `{:error, :no_branch}` if no such branch exists.

- `ObjectStore.update_branch(server, name, expected_hash, new_hash)` performs an atomic compare-and-swap: it moves branch `name` to `new_hash` **only if** the branch currently points at `expected_hash`. On success returns `{:ok, new_hash}` (including the no-op case where `new_hash` equals the current head). If the branch does not exist, return `{:error, :no_branch}`. If `new_hash` is not an existing stored object, return `{:error, :not_found}`. If the branch exists but does not currently point at `expected_hash`, return `{:error, :conflict}` and leave the branch unchanged.

- `ObjectStore.delete_branch(server, name)` removes a branch and returns `:ok`, or `{:error, :no_branch}` if it does not exist.

- `ObjectStore.list_branches(server)` returns a map of branch name → commit hash for all branches — `%{}` for a fresh store, and reflecting creations, compare-and-swap moves, and deletions.

- `ObjectStore.gc(server)` garbage-collects unreferenced objects and returns `{:ok, removed_count}`, the number of objects deleted (`{:ok, 0}` when nothing is unreachable, so repeated calls converge). An object is **reachable** if any of the following holds: (a) it is the object a branch points at directly (commit or blob); (b) it is an ancestor commit found by following `parent` links transitively — through arbitrarily many hops — from any branch head; or (c) it is the tree object referenced (via `tree_hash`) by any reachable commit, including trees of ancestor commits. Every stored object that is not reachable is deleted; with no branches at all, everything is swept. In particular, a loose blob that is not referenced as some reachable commit's tree is unreachable and will be removed.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- Commit serialization must be deterministic and include the tree, parent (use the literal `nil` when there is no parent), author, and message so that ancestry and tree references can be recovered when computing reachability.
- All stored objects (blobs and commits) live in the same flat hash map; branches live in a separate map.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
