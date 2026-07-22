defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with a directed acyclic graph (DAG) commit history.

  Objects are arbitrary binaries keyed by the lowercase hex SHA-1 digest of their
  contents. Blobs and commits share one flat storage map — there is no type
  distinction at the storage layer.

  Commits may have any number of parents:

    * `[]` — a root commit
    * `[parent]` — an ordinary commit
    * `[p1, p2 | _]` — a merge commit

  Because history is a graph rather than a chain, `log/2` performs a reverse
  topological traversal over all reachable ancestors, and `merge_base/3` finds a
  lowest common ancestor of two commits.
  """

  use GenServer

  @typedoc "A lowercase hex SHA-1 digest, 40 characters long."
  @type hash :: String.t()

  @typedoc "A single entry produced by `log/2`."
  @type log_entry :: %{
          hash: hash(),
          tree: hash(),
          parents: [hash()],
          author: String.t(),
          message: String.t()
        }

  @typedoc "A started server reference."
  @type server :: GenServer.server()

  # Client API

  @doc """
  Starts the object store process.

  Accepts a `:name` option for process registration. Works with `[]`, in which case
  the process is addressed by its pid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, rest} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, rest)
      name -> GenServer.start_link(__MODULE__, rest, name: name)
    end
  end

  @doc """
  Stores `content` and returns `{:ok, hash}` where `hash` is its SHA-1 hex digest.

  Storing the same content twice is idempotent: the same hash is returned and no
  data is duplicated.
  """
  @spec store(server(), binary()) :: {:ok, hash()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the object stored under `hash`.

  Returns `{:ok, content}` with the exact bytes originally stored, or
  `{:error, :not_found}` when the hash is unknown.
  """
  @spec retrieve(server(), hash()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates a commit object referencing `tree_hash` with the given `parents`.

  `parents` is a list of parent commit hashes: `[]` for a root commit, one element
  for an ordinary commit, two or more for a merge commit. The serialization is
  deterministic and printable, and embeds `tree_hash`, `author` and `message`
  verbatim. Returns `{:ok, commit_hash}`.
  """
  @spec commit(server(), hash(), [hash()], String.t(), String.t()) :: {:ok, hash()}
  def commit(server, tree_hash, parents, message, author)
      when is_binary(tree_hash) and is_list(parents) and is_binary(message) and
             is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parents, message, author})
  end

  @doc """
  Returns `{:ok, entries}` describing every commit reachable from `commit_hash`.

  Entries are ordered newest-to-oldest: `commit_hash` is first and every commit
  appears before all of its ancestors. Each reachable commit appears exactly once,
  even in diamond-shaped histories. Returns `{:error, :not_found}` when
  `commit_hash` is unknown.
  """
  @spec log(server(), hash()) :: {:ok, [log_entry()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

  @doc """
  Returns `{:ok, base_hash}` for a lowest common ancestor of `hash_a` and `hash_b`.

  A commit is considered an ancestor of itself. Returns `{:error, :not_found}` if
  either commit is unknown, or `{:error, :no_merge_base}` when the two commits
  share no common ancestor.
  """
  @spec merge_base(server(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found} | {:error, :no_merge_base}
  def merge_base(server, hash_a, hash_b) when is_binary(hash_a) and is_binary(hash_b) do
    GenServer.call(server, {:merge_base, hash_a, hash_b})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{objects: %{}}}
  end

  @impl true
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
      {:ok, _commit} -> {:reply, {:ok, traverse(state, commit_hash)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:merge_base, hash_a, hash_b}, _from, state) do
    {:reply, do_merge_base(state, hash_a, hash_b), state}
  end

  # Storage helpers

  @spec put_object(map(), binary()) :: {hash(), map()}
  defp put_object(state, content) do
    hash = hash_content(content)
    {hash, %{state | objects: Map.put_new(state.objects, hash, content)}}
  end

  @spec hash_content(binary()) :: hash()
  defp hash_content(content) do
    :crypto.hash(:sha, content) |> Base.encode16(case: :lower)
  end

  # Commit serialization

  @spec serialize_commit(hash(), [hash()], String.t(), String.t()) :: String.t()
  defp serialize_commit(tree_hash, parents, message, author) do
    parent_lines = Enum.map(parents, fn parent -> "parent #{parent}\n" end)

    IO.iodata_to_binary([
      "tree ",
      tree_hash,
      "\n",
      parent_lines,
      "author ",
      author,
      "\n",
      "\n",
      message,
      "\n"
    ])
  end

  @spec parse_commit(hash(), String.t()) :: log_entry()
  defp parse_commit(hash, content) do
    [header, message] = split_header(content)
    lines = String.split(header, "\n", trim: true)

    tree =
      Enum.find_value(lines, "", fn
        "tree " <> value -> value
        _other -> nil
      end)

    parents =
      Enum.flat_map(lines, fn
        "parent " <> value -> [value]
        _other -> []
      end)

    author =
      Enum.find_value(lines, "", fn
        "author " <> value -> value
        _other -> nil
      end)

    %{hash: hash, tree: tree, parents: parents, author: author, message: message}
  end

  @spec split_header(String.t()) :: [String.t()]
  defp split_header(content) do
    case String.split(content, "\n\n", parts: 2) do
      [header, rest] -> [header, String.replace_suffix(rest, "\n", "")]
      [header] -> [header, ""]
    end
  end

  @spec fetch_commit(map(), hash()) :: {:ok, log_entry()} | :error
  defp fetch_commit(state, hash) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:ok, parse_commit(hash, content)}
      :error -> :error
    end
  end

  # Graph traversal

  # Depth-first post-order traversal, reversed: guarantees every commit appears
  # before all of its ancestors, with the starting commit first.
  @spec traverse(map(), hash()) :: [log_entry()]
  defp traverse(state, root) do
    {order, _seen} = visit(state, root, [], MapSet.new())
    Enum.reverse(order)
  end

  @spec visit(map(), hash(), [log_entry()], MapSet.t()) :: {[log_entry()], MapSet.t()}
  defp visit(state, hash, acc, seen) do
    cond do
      MapSet.member?(seen, hash) ->
        {acc, seen}

      true ->
        case fetch_commit(state, hash) do
          :error ->
            {acc, seen}

          {:ok, commit} ->
            seen = MapSet.put(seen, hash)

            {acc, seen} =
              Enum.reduce(commit.parents, {acc, seen}, fn parent, {acc, seen} ->
                visit(state, parent, acc, seen)
              end)

            {[commit | acc], seen}
        end
    end
  end

  @spec ancestors(map(), hash()) :: MapSet.t()
  defp ancestors(state, hash) do
    collect_ancestors(state, [hash], MapSet.new())
  end

  @spec collect_ancestors(map(), [hash()], MapSet.t()) :: MapSet.t()
  defp collect_ancestors(_state, [], seen), do: seen

  defp collect_ancestors(state, [hash | rest], seen) do
    if MapSet.member?(seen, hash) do
      collect_ancestors(state, rest, seen)
    else
      case fetch_commit(state, hash) do
        :error ->
          collect_ancestors(state, rest, seen)

        {:ok, commit} ->
          collect_ancestors(state, commit.parents ++ rest, MapSet.put(seen, hash))
      end
    end
  end

  # Merge base

  @spec do_merge_base(map(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found} | {:error, :no_merge_base}
  defp do_merge_base(state, hash_a, hash_b) do
    with {:ok, _a} <- fetch_commit(state, hash_a),
         {:ok, _b} <- fetch_commit(state, hash_b) do
      common =
        state
        |> ancestors(hash_a)
        |> MapSet.intersection(ancestors(state, hash_b))

      case lowest_common(state, common) do
        nil -> {:error, :no_merge_base}
        base -> {:ok, base}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  # A lowest common ancestor is a common ancestor that is not a proper ancestor of
  # any other common ancestor.
  @spec lowest_common(map(), MapSet.t()) :: hash() | nil
  defp lowest_common(state, common) do
    dominated =
      Enum.reduce(common, MapSet.new(), fn hash, acc ->
        proper =
          state
          |> ancestors(hash)
          |> MapSet.delete(hash)
          |> MapSet.intersection(common)

        MapSet.union(acc, proper)
      end)

    common
    |> MapSet.difference(dominated)
    |> Enum.sort()
    |> List.first()
  end
end