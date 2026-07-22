defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with a DAG-shaped commit history.

  Objects (arbitrary binaries) are stored in a single flat map keyed by the
  lowercase hex SHA-1 digest of their raw content. Commits are ordinary objects
  whose content is a deterministic text serialization of the commit fields:

      tree <tree_hash>
      parent <parent_hash>   # zero, one, or many, in the given order
      author <author>

      <message>

  Because commits are just objects, they are addressed by the SHA-1 of that
  serialization. The same tree, the same parents in the same order, the same
  message and the same author therefore always produce the same commit hash,
  while any change to the parent list produces a different one.

  A commit may have any number of parents:

    * `[]` — a root commit;
    * `[parent]` — an ordinary commit;
    * `[p1, p2 | _]` — a merge commit.

  This makes the history a directed acyclic graph rather than a linear chain, so
  `log/2` performs a reverse-topological graph walk over everything reachable
  from a commit, and `merge_base/3` finds a lowest common ancestor of two
  commits.
  """

  use GenServer

  @type hash :: String.t()
  @type entry :: %{
          hash: hash(),
          tree: hash(),
          parents: [hash()],
          author: String.t(),
          message: String.t()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the object store process.

  Accepts the standard `GenServer` options; in particular `:name` may be given
  to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Stores `content` and returns `{:ok, hash}` where `hash` is its lowercase hex
  SHA-1 digest.

  Storing the same content twice is idempotent: it yields the same hash and does
  not duplicate the underlying data.
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
  Creates a commit object pointing at `tree_hash` with the given `parents`.

  `parents` is a list of parent commit hashes: `[]` for a root commit, a single
  element for an ordinary commit, and two or more for a merge commit. Returns
  `{:ok, commit_hash}`.
  """
  @spec commit(GenServer.server(), hash(), [hash()], String.t(), String.t()) :: {:ok, hash()}
  def commit(server, tree_hash, parents, message, author)
      when is_binary(tree_hash) and is_list(parents) and is_binary(message) and
             is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parents, message, author})
  end

  @doc """
  Returns `{:ok, entries}` describing every commit reachable from `commit_hash`
  by transitively following parent links, including `commit_hash` itself.

  Entries are ordered newest-to-oldest: the starting commit is first and every
  commit appears before all of its ancestors (a reverse-topological order).
  Returns `{:error, :not_found}` if `commit_hash` is unknown.
  """
  @spec log(GenServer.server(), hash()) :: {:ok, [entry()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

  @doc """
  Returns `{:ok, base_hash}` with a lowest common ancestor of `hash_a` and
  `hash_b` — a common ancestor that is not a proper ancestor of any other common
  ancestor. A commit is considered an ancestor of itself.

  Returns `{:error, :not_found}` if either commit is unknown, or
  `{:error, :no_merge_base}` if the commits share no common ancestor.
  """
  @spec merge_base(GenServer.server(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found | :no_merge_base}
  def merge_base(server, hash_a, hash_b) when is_binary(hash_a) and is_binary(hash_b) do
    GenServer.call(server, {:merge_base, hash_a, hash_b})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts), do: {:ok, %{objects: %{}}}

  @impl GenServer
  def handle_call({:store, content}, _from, state) do
    {hash, state} = put_object(state, content)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree_hash, parents, message, author}, _from, state) do
    content = serialize_commit(tree_hash, parents, message, author)
    {hash, state} = put_object(state, content)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:log, commit_hash}, _from, state) do
    case fetch_commit(state, commit_hash) do
      {:ok, _entry} -> {:reply, {:ok, walk(state, commit_hash)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:merge_base, hash_a, hash_b}, _from, state) do
    with {:ok, _a} <- fetch_commit(state, hash_a),
         {:ok, _b} <- fetch_commit(state, hash_b) do
      {:reply, do_merge_base(state, hash_a, hash_b), state}
    else
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Storage helpers
  # ---------------------------------------------------------------------------

  defp put_object(state, content) do
    hash = hash_content(content)
    {hash, %{state | objects: Map.put_new(state.objects, hash, content)}}
  end

  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Commit serialization / parsing
  # ---------------------------------------------------------------------------

  defp serialize_commit(tree_hash, parents, message, author) do
    parent_lines = Enum.map(parents, fn parent -> "parent #{parent}\n" end)

    IO.iodata_to_binary([
      "tree #{tree_hash}\n",
      parent_lines,
      "author #{author}\n",
      "\n",
      message
    ])
  end

  defp fetch_commit(state, hash) do
    with {:ok, content} <- Map.fetch(state.objects, hash),
         {:ok, entry} <- parse_commit(hash, content) do
      {:ok, entry}
    else
      _other -> :error
    end
  end

  defp parse_commit(hash, content) do
    case String.split(content, "\n\n", parts: 2) do
      [header, message] -> parse_header(hash, header, message)
      _other -> :error
    end
  end

  defp parse_header(hash, header, message) do
    lines = String.split(header, "\n", trim: true)

    entry =
      Enum.reduce(lines, %{hash: hash, tree: nil, parents: [], author: "", message: message}, fn
        "tree " <> tree, acc -> %{acc | tree: tree}
        "parent " <> parent, acc -> %{acc | parents: acc.parents ++ [parent]}
        "author " <> author, acc -> %{acc | author: author}
        _line, acc -> acc
      end)

    if is_binary(entry.tree), do: {:ok, entry}, else: :error
  end

  # ---------------------------------------------------------------------------
  # Graph walking
  # ---------------------------------------------------------------------------

  # Reverse-topological (newest-to-oldest) order over everything reachable from
  # `root`: a depth-first post-order over parents, reversed, guarantees every
  # commit precedes all of its ancestors.
  defp walk(state, root) do
    {order, _seen} = dfs(state, root, [], MapSet.new())
    Enum.reverse(order)
  end

  defp dfs(state, hash, order, seen) do
    cond do
      MapSet.member?(seen, hash) ->
        {order, seen}

      true ->
        case fetch_commit(state, hash) do
          {:ok, entry} ->
            seen = MapSet.put(seen, hash)

            {order, seen} =
              Enum.reduce(entry.parents, {order, seen}, fn parent, {acc_order, acc_seen} ->
                dfs(state, parent, acc_order, acc_seen)
              end)

            {[entry | order], seen}

          :error ->
            {order, MapSet.put(seen, hash)}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Merge base
  # ---------------------------------------------------------------------------

  defp do_merge_base(state, hash_a, hash_b) do
    ancestors_a = ancestor_set(state, hash_a)
    ancestors_b = ancestor_set(state, hash_b)
    common = MapSet.intersection(ancestors_a, ancestors_b)

    if MapSet.size(common) == 0 do
      {:error, :no_merge_base}
    else
      # A lowest common ancestor is a common ancestor that is not a *proper*
      # ancestor of any other common ancestor. Walking from `hash_a` in
      # newest-to-oldest order, the first common commit encountered whose
      # descendants-within-common are empty is such a commit.
      redundant =
        Enum.reduce(common, MapSet.new(), fn hash, acc ->
          case fetch_commit(state, hash) do
            {:ok, entry} ->
              Enum.reduce(entry.parents, acc, fn parent, inner ->
                MapSet.union(inner, MapSet.intersection(ancestor_set(state, parent), common))
              end)

            :error ->
              acc
          end
        end)

      lowest = MapSet.difference(common, redundant)

      case first_in_walk_order(state, hash_a, lowest) do
        nil -> {:error, :no_merge_base}
        hash -> {:ok, hash}
      end
    end
  end

  defp first_in_walk_order(state, root, candidates) do
    state
    |> walk(root)
    |> Enum.find_value(fn entry ->
      if MapSet.member?(candidates, entry.hash), do: entry.hash
    end)
  end

  defp ancestor_set(state, hash) do
    state
    |> walk(hash)
    |> Enum.map(& &1.hash)
    |> MapSet.new()
  end
end