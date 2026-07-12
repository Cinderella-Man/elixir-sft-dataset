# Task: Implement `walk_log/3`

You are working on the `ObjectStore` GenServer module below — a content-addressable
object store modeled on Git. Everything is implemented except the private recursive
helper `walk_log/3`, which powers the public `log/2` API.

Implement the private `walk_log/3` function. It walks a commit's parent chain and
accumulates commit maps from newest to oldest. It takes the state map (SHA-1 hex →
stored binary), the current commit `hash`, and an `acc` list of already-visited
entries (built up in reverse, newest-first-prepended, so the newest commit ends up
last in `acc`).

Behavior:

- **Base case — `nil` hash:** when the hash is `nil` (the parent chain has ended),
  the walk is complete. Return `{:ok, entries}` where `entries` is `acc` reversed,
  giving newest-to-oldest order.
- **Lookup the hash** in `state` with `Map.fetch/2`:
  - If it is **not found and `acc` is empty**, the caller passed a starting hash that
    does not exist. Return `{:error, :not_found}`.
  - If it is **not found but `acc` is non-empty**, this is a dangling parent reference
    part-way through the chain. Stop gracefully and return `{:ok, Enum.reverse(acc)}`.
  - If it is **found**, parse the stored content with `parse_commit/1`, build an entry
    map with the keys `:hash` (the current hash), `:tree`, `:parent`, `:author`, and
    `:message` (the parsed fields), then recurse on the commit's `parent`, prepending
    the new entry onto `acc`.

The recursion naturally terminates when it follows a `parent` of `nil` into the base
case.

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

  defp walk_log(_state, nil, acc) do
    # TODO
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