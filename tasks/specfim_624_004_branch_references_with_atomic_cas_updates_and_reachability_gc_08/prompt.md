# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`update_branch/4` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `update_branch/4` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `update_branch/4` missing

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with mutable named branch references and
  reachability-based garbage collection, modeled loosely on Git.

  Objects (blobs and commits) are immutable and addressed by the SHA-1 hex
  digest of their raw bytes. They all live in a single flat map from hash to
  binary content.

  Branches are mutable named pointers to commit hashes. They live in a separate
  map and are updated with an atomic compare-and-swap.

  Garbage collection walks the reachability graph starting from every branch
  head — following `parent` links to ancestor commits and `tree_hash`
  references to tree objects — and deletes every stored object that is not
  reachable.
  """

  use GenServer

  @typedoc "A SHA-1 hex digest (lowercase)."
  @type hash :: String.t()

  @typedoc "Internal server state."
  @type state :: %{
          objects: %{optional(hash) => binary()},
          branches: %{optional(String.t()) => hash}
        }

  # Public API

  @doc """
  Starts the object store process.

  Accepts an optional `:name` for process registration; all other options are
  passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, :ok, opts)
      name -> GenServer.start_link(__MODULE__, :ok, [{:name, name} | opts])
    end
  end

  @doc """
  Stores raw `content`, returning `{:ok, hash}` where `hash` is its SHA-1 hex
  digest. Idempotent: identical content always yields the same hash and is not
  duplicated.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, hash}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the content stored under `hash`, or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), hash) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates and stores a commit object referencing `tree_hash` with parent
  `parent_hash` (or `nil` for a root commit), along with `message` and
  `author`. Returns `{:ok, commit_hash}`. Deterministic: identical arguments
  always produce the same commit hash.
  """
  @spec commit(GenServer.server(), hash, hash | nil, String.t(), String.t()) :: {:ok, hash}
  def commit(server, tree_hash, parent_hash, message, author)
      when is_binary(tree_hash) and (is_binary(parent_hash) or is_nil(parent_hash)) and
             is_binary(message) and is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end

  @doc """
  Creates a branch `name` pointing at `commit_hash`.

  Returns `{:ok, name}` on success, `{:error, :exists}` if the branch already
  exists, or `{:error, :not_found}` if `commit_hash` is not a stored object.
  """
  @spec create_branch(GenServer.server(), String.t(), hash) ::
          {:ok, String.t()} | {:error, :exists | :not_found}
  def create_branch(server, name, commit_hash) when is_binary(name) and is_binary(commit_hash) do
    GenServer.call(server, {:create_branch, name, commit_hash})
  end

  @doc """
  Returns `{:ok, commit_hash}` for the commit branch `name` points at, or
  `{:error, :no_branch}` if there is no such branch.
  """
  @spec branch_head(GenServer.server(), String.t()) :: {:ok, hash} | {:error, :no_branch}
  def branch_head(server, name) when is_binary(name) do
    GenServer.call(server, {:branch_head, name})
  end

  @doc """
  Atomically moves branch `name` from `expected_hash` to `new_hash`.

  Returns `{:ok, new_hash}` on success. Returns `{:error, :no_branch}` if the
  branch does not exist, `{:error, :not_found}` if `new_hash` is not a stored
  object, or `{:error, :conflict}` (leaving the branch unchanged) if the branch
  does not currently point at `expected_hash`.
  """
  # TODO: @spec
  def update_branch(server, name, expected_hash, new_hash)
      when is_binary(name) and is_binary(expected_hash) and is_binary(new_hash) do
    GenServer.call(server, {:update_branch, name, expected_hash, new_hash})
  end

  @doc """
  Deletes branch `name`. Returns `:ok`, or `{:error, :no_branch}` if it does
  not exist.
  """
  @spec delete_branch(GenServer.server(), String.t()) :: :ok | {:error, :no_branch}
  def delete_branch(server, name) when is_binary(name) do
    GenServer.call(server, {:delete_branch, name})
  end

  @doc """
  Returns a map of branch name to commit hash for all branches.
  """
  @spec list_branches(GenServer.server()) :: %{optional(String.t()) => hash}
  def list_branches(server) do
    GenServer.call(server, :list_branches)
  end

  @doc """
  Garbage-collects unreferenced objects, returning `{:ok, removed_count}`.

  An object is reachable if it is a branch head, an ancestor commit reachable
  by following `parent` links from a branch head, or the tree referenced by a
  reachable commit. All other stored objects are deleted.
  """
  @spec gc(GenServer.server()) :: {:ok, non_neg_integer()}
  def gc(server) do
    GenServer.call(server, :gc)
  end

  # GenServer callbacks

  @impl true
  @spec init(:ok) :: {:ok, state}
  def init(:ok) do
    {:ok, %{objects: %{}, branches: %{}}}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree_hash, parent_hash, message, author}, _from, state) do
    content = serialize_commit(tree_hash, parent_hash, message, author)
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:create_branch, name, commit_hash}, _from, state) do
    cond do
      Map.has_key?(state.branches, name) ->
        {:reply, {:error, :exists}, state}

      not Map.has_key?(state.objects, commit_hash) ->
        {:reply, {:error, :not_found}, state}

      true ->
        branches = Map.put(state.branches, name, commit_hash)
        {:reply, {:ok, name}, %{state | branches: branches}}
    end
  end

  def handle_call({:branch_head, name}, _from, state) do
    case Map.fetch(state.branches, name) do
      {:ok, commit_hash} -> {:reply, {:ok, commit_hash}, state}
      :error -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call({:update_branch, name, expected_hash, new_hash}, _from, state) do
    cond do
      not Map.has_key?(state.branches, name) ->
        {:reply, {:error, :no_branch}, state}

      not Map.has_key?(state.objects, new_hash) ->
        {:reply, {:error, :not_found}, state}

      Map.fetch!(state.branches, name) != expected_hash ->
        {:reply, {:error, :conflict}, state}

      true ->
        branches = Map.put(state.branches, name, new_hash)
        {:reply, {:ok, new_hash}, %{state | branches: branches}}
    end
  end

  def handle_call({:delete_branch, name}, _from, state) do
    case Map.has_key?(state.branches, name) do
      true -> {:reply, :ok, %{state | branches: Map.delete(state.branches, name)}}
      false -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call(:list_branches, _from, state) do
    {:reply, state.branches, state}
  end

  def handle_call(:gc, _from, state) do
    reachable = reachable_set(state)

    {kept, removed_count} =
      Enum.reduce(state.objects, {%{}, 0}, fn {hash, content}, {acc, count} ->
        case MapSet.member?(reachable, hash) do
          true -> {Map.put(acc, hash, content), count}
          false -> {acc, count + 1}
        end
      end)

    {:reply, {:ok, removed_count}, %{state | objects: kept}}
  end

  # Internal helpers

  @spec hash_content(binary()) :: hash
  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  @spec serialize_commit(hash, hash | nil, String.t(), String.t()) :: binary()
  defp serialize_commit(tree_hash, parent_hash, message, author) do
    parent_line = if is_nil(parent_hash), do: "parent nil", else: "parent #{parent_hash}"

    Enum.join(
      [
        "commit",
        "tree #{tree_hash}",
        parent_line,
        "author #{author}",
        "",
        message
      ],
      "\n"
    )
  end

  @spec parse_commit(binary()) :: {:ok, %{tree: hash, parent: hash | nil}} | :error
  defp parse_commit(content) do
    case String.split(content, "\n") do
      ["commit", "tree " <> tree, "parent " <> parent | _rest] ->
        parent = if parent == "nil", do: nil, else: parent
        {:ok, %{tree: tree, parent: parent}}

      _other ->
        :error
    end
  end

  @spec reachable_set(state) :: MapSet.t(hash)
  defp reachable_set(state) do
    heads = Map.values(state.branches)
    walk(heads, state.objects, MapSet.new())
  end

  @spec walk([hash], %{optional(hash) => binary()}, MapSet.t(hash)) :: MapSet.t(hash)
  defp walk([], _objects, acc), do: acc

  defp walk([hash | rest], objects, acc) do
    cond do
      MapSet.member?(acc, hash) ->
        walk(rest, objects, acc)

      not Map.has_key?(objects, hash) ->
        walk(rest, objects, acc)

      true ->
        acc = MapSet.put(acc, hash)
        extra = commit_refs(Map.fetch!(objects, hash))
        walk(extra ++ rest, objects, acc)
    end
  end

  @spec commit_refs(binary()) :: [hash]
  defp commit_refs(content) do
    case parse_commit(content) do
      {:ok, %{tree: tree, parent: parent}} ->
        refs = [tree]
        if is_nil(parent), do: refs, else: [parent | refs]

      :error ->
        []
    end
  end
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
