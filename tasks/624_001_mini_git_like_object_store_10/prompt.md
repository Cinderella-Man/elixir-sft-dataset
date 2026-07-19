# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `log` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store, similar in spirit to Git's object model.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It should accept a `:name` option for process registration — with `name: some_atom` the process must be findable via `Process.whereis(some_atom)`, and every other API function must accept that name in place of a pid. Called with no `:name` (e.g. `start_link([])`) it starts an unregistered process. Each store instance keeps its own independent object map — content stored in one is not visible from another. Internal state should be an in-memory map of SHA-1 hex digest → stored binary content.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string (including the empty string and binaries containing null bytes or arbitrary bytes), computes its SHA-1 hash (lowercase hex, 40 characters), persists the raw content keyed by that hash, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not duplicate data.

- `ObjectStore.retrieve(server, hash)` which looks up a hash and returns `{:ok, content}` if found, or `{:error, :not_found}` if the hash does not exist in the store. Content must come back byte-for-byte identical to what was stored. This works for any object — blobs, trees and commits alike — returning the raw stored bytes.

- `ObjectStore.tree(server, entries)` which takes a list of entry maps, each containing the keys `:name` (a string filename), `:hash` (a SHA-1 hex string referencing an already-stored object), and `:type` (either `:blob` or `:tree`). The function must build a deterministic canonical text representation of the tree by sorting entries by `:name`, serialize it into a single binary string, store that string as an object via the same `store` mechanism, and return `{:ok, tree_hash}`. Two calls with the same entries in any order must produce the same hash, and trees whose entries differ in name, hash or type must produce different hashes. An empty entries list is valid: it must still return `{:ok, tree_hash}` for a retrievable object.

- `ObjectStore.commit(server, tree_hash, parent_hash, message, author)` which creates a commit object. `tree_hash` is the SHA-1 of a tree object. `parent_hash` is either a SHA-1 string of the parent commit or `nil` for the initial commit. `message` is a string and `author` is a string. Build a deterministic text representation containing all four fields, store it as an object, and return `{:ok, commit_hash}`. Calling `commit` twice with identical arguments must yield the same hash.

- `ObjectStore.log(server, commit_hash)` which walks the parent chain starting from the given commit hash. It must return `{:ok, entries}` where `entries` is a list of maps, each containing `:hash`, `:message`, `:author`, `:tree`, and `:parent`. `:hash` is the commit's own hash, `:tree`, `:message` and `:author` are exactly the values passed to `commit` (byte-for-byte, including messages that contain newlines, blank lines or `<`/`@` characters), and `:parent` is the parent commit's hash string or `nil` for the initial commit. The list is ordered from newest to oldest. If the starting hash is not found, return `{:error, :not_found}`. Walking stops when a commit with a `nil` parent is reached.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- Tree serialization must sort entries alphabetically by name before hashing so that entry order in the input list does not affect the resulting hash.
- Commit serialization must use a fixed field order (tree, parent, author, message) so the hash is deterministic. Put the message last and parse it as the remainder, so multi-line commit messages round-trip through `log` unchanged.
- All stored objects (blobs, trees, commits) live in the same flat hash map — there is no type distinction at the storage layer.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `log` missing

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
    # TODO
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

Give me only the complete implementation of `log` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
