defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with mutable named branch references and
  reachability-based garbage collection.

  The store keeps two pieces of state:

    * `objects` — a flat map of SHA-1 hex digest (lowercase) to the raw binary
      content of the object. Objects are immutable and content-addressed, so
      storing the same content twice is idempotent.
    * `branches` — a map of branch name (string) to the SHA-1 hex digest of the
      commit the branch points at. Branches are mutable and are moved with an
      atomic compare-and-swap (`update_branch/4`).

  Commits are ordinary objects whose content is a deterministic textual
  serialization referencing a tree object and (optionally) a parent commit.
  Because the serialization is deterministic, the same commit arguments always
  produce the same commit hash.

  Garbage collection (`gc/1`) walks every branch head, follows `parent` links to
  collect ancestor commits, and marks each reachable commit's `tree` object as
  reachable too. Every stored object that is not in that reachable set is
  deleted. A loose blob that is not the tree of some reachable commit is
  therefore unreachable and will be swept away.
  """

  use GenServer

  @type hash :: String.t()
  @type branch :: String.t()

  defstruct objects: %{}, branches: %{}

  @typep state :: %__MODULE__{objects: %{hash() => binary()}, branches: %{branch() => hash()}}

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the object store process.

  Accepts the standard `GenServer` options; in particular `:name` may be given to
  register the process under a name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Stores `content` and returns `{:ok, hash}` where `hash` is the lowercase SHA-1
  hex digest of the content.

  Storing is idempotent: identical content always maps to the same hash and is
  never duplicated.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, hash()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the object stored under `hash`.

  Returns `{:ok, content}` or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), hash()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates a commit object referencing `tree_hash`, with `parent_hash` (a commit
  hash, or `nil` for a root commit), a `message` and an `author`.

  The commit is serialized deterministically, stored as a regular object and its
  hash returned as `{:ok, commit_hash}`.
  """
  @spec commit(GenServer.server(), hash(), hash() | nil, String.t(), String.t()) :: {:ok, hash()}
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
  @spec create_branch(GenServer.server(), branch(), hash()) ::
          {:ok, branch()} | {:error, :exists | :not_found}
  def create_branch(server, name, commit_hash) when is_binary(name) and is_binary(commit_hash) do
    GenServer.call(server, {:create_branch, name, commit_hash})
  end

  @doc """
  Returns `{:ok, commit_hash}` for the commit branch `name` points at, or
  `{:error, :no_branch}` when the branch does not exist.
  """
  @spec branch_head(GenServer.server(), branch()) :: {:ok, hash()} | {:error, :no_branch}
  def branch_head(server, name) when is_binary(name) do
    GenServer.call(server, {:branch_head, name})
  end

  @doc """
  Atomically moves branch `name` from `expected_hash` to `new_hash`
  (compare-and-swap).

  Returns `{:ok, new_hash}` on success, `{:error, :no_branch}` if the branch does
  not exist, `{:error, :not_found}` if `new_hash` is not a stored object, or
  `{:error, :conflict}` if the branch does not currently point at
  `expected_hash` (in which case the branch is left unchanged).
  """
  @spec update_branch(GenServer.server(), branch(), hash() | nil, hash()) ::
          {:ok, hash()} | {:error, :no_branch | :not_found | :conflict}
  def update_branch(server, name, expected_hash, new_hash)
      when is_binary(name) and is_binary(new_hash) do
    GenServer.call(server, {:update_branch, name, expected_hash, new_hash})
  end

  @doc """
  Deletes branch `name`.

  Returns `:ok`, or `{:error, :no_branch}` when the branch does not exist.
  """
  @spec delete_branch(GenServer.server(), branch()) :: :ok | {:error, :no_branch}
  def delete_branch(server, name) when is_binary(name) do
    GenServer.call(server, {:delete_branch, name})
  end

  @doc """
  Returns a map of branch name to commit hash for every branch in the store.
  """
  @spec list_branches(GenServer.server()) :: %{branch() => hash()}
  def list_branches(server) do
    GenServer.call(server, :list_branches)
  end

  @doc """
  Garbage-collects every object that is not reachable from a branch head.

  Reachable objects are: branch head commits, their ancestors (via `parent`
  links) and the tree object of every reachable commit. Returns
  `{:ok, removed_count}` with the number of objects deleted.
  """
  @spec gc(GenServer.server()) :: {:ok, non_neg_integer()}
  def gc(server) do
    GenServer.call(server, :gc)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = hash_content(content)
    {:reply, {:ok, hash}, put_object(state, hash, content)}
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
    {:reply, {:ok, hash}, put_object(state, hash, content)}
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
    case Map.pop(state.branches, name) do
      {nil, _branches} -> {:reply, {:error, :no_branch}, state}
      {_hash, branches} -> {:reply, :ok, %{state | branches: branches}}
    end
  end

  def handle_call(:list_branches, _from, state) do
    {:reply, state.branches, state}
  end

  def handle_call(:gc, _from, state) do
    reachable = reachable_objects(state)

    kept = Map.take(state.objects, MapSet.to_list(reachable))
    removed = map_size(state.objects) - map_size(kept)

    {:reply, {:ok, removed}, %{state | objects: kept}}
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec put_object(state(), hash(), binary()) :: state()
  defp put_object(state, hash, content) do
    %{state | objects: Map.put_new(state.objects, hash, content)}
  end

  @spec hash_content(binary()) :: hash()
  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  @spec serialize_commit(hash(), hash() | nil, String.t(), String.t()) :: binary()
  defp serialize_commit(tree_hash, parent_hash, message, author) do
    parent = if is_nil(parent_hash), do: "nil", else: parent_hash

    """
    commit
    tree #{tree_hash}
    parent #{parent}
    author #{author}

    #{message}
    """
  end

  @spec parse_commit(binary()) :: {:ok, %{tree: hash(), parent: hash() | nil}} | :error
  defp parse_commit(content) when is_binary(content) do
    lines = String.split(content, "\n")

    with ["commit" | rest] <- lines,
         {:ok, tree} <- header_value(rest, "tree "),
         {:ok, parent} <- header_value(rest, "parent ") do
      {:ok, %{tree: tree, parent: if(parent == "nil", do: nil, else: parent)}}
    else
      _other -> :error
    end
  end

  defp parse_commit(_content), do: :error

  @spec header_value([String.t()], String.t()) :: {:ok, String.t()} | :error
  defp header_value(lines, prefix) do
    Enum.find_value(lines, :error, fn line ->
      case line do
        ^prefix <> value -> {:ok, value}
        _other -> nil
      end
    end)
  end

  @spec reachable_objects(state()) :: MapSet.t(hash())
  defp reachable_objects(state) do
    state.branches
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn head, acc -> walk_commit(state, head, acc) end)
  end

  @spec walk_commit(state(), hash() | nil, MapSet.t(hash())) :: MapSet.t(hash())
  defp walk_commit(_state, nil, acc), do: acc

  defp walk_commit(state, hash, acc) do
    cond do
      MapSet.member?(acc, hash) ->
        acc

      not Map.has_key?(state.objects, hash) ->
        acc

      true ->
        acc = MapSet.put(acc, hash)

        case parse_commit(Map.fetch!(state.objects, hash)) do
          {:ok, %{tree: tree, parent: parent}} ->
            acc = if Map.has_key?(state.objects, tree), do: MapSet.put(acc, tree), else: acc
            walk_commit(state, parent, acc)

          :error ->
            acc
        end
    end
  end
end