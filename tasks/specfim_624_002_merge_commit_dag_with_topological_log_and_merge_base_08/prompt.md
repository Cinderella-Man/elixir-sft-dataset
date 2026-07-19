# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`sha1_hex/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `sha1_hex/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `sha1_hex/1` missing

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with a directed-acyclic-graph (DAG)
  commit history.

  Every object — whether a blob of arbitrary content or a serialized commit —
  is stored in a single flat map keyed by the lowercase hexadecimal SHA-1
  digest of its raw bytes. Because the key is derived from the content,
  storing identical content twice is idempotent.

  Commits may have any number of parents:

    * `[]` for a root commit,
    * a single parent for an ordinary commit,
    * two or more parents for a merge commit.

  This makes the commit history a DAG rather than a linear chain, so `log/2`
  performs a graph walk (reverse-topological order) and `merge_base/3` finds a
  lowest common ancestor of two commits.
  """

  use GenServer

  @typedoc "A GenServer reference (pid or registered name)."
  @type server :: GenServer.server()

  @typedoc "A lowercase hexadecimal SHA-1 digest."
  @type hash :: String.t()

  @typedoc "A single commit description returned by `log/2`."
  @type entry :: %{
          hash: hash(),
          tree: hash(),
          parents: [hash()],
          author: String.t(),
          message: String.t()
        }

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the object store process.

  Accepts a `:name` option for process registration; any other options are
  ignored. The internal state is an in-memory map of SHA-1 hex digest to the
  stored raw binary content.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    gen_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  @doc """
  Stores `content`, returning `{:ok, hash}`.

  The hash is the lowercase hexadecimal SHA-1 digest of `content`. Storing the
  same content again returns the same hash without duplicating data.
  """
  @spec store(server(), binary()) :: {:ok, hash()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the content stored under `hash`.

  Returns `{:ok, content}` if present, otherwise `{:error, :not_found}`.
  """
  @spec retrieve(server(), hash()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates a commit object and stores it, returning `{:ok, commit_hash}`.

  `tree_hash` references an already-stored object. `parents` is a list of
  parent commit hashes (`[]` for a root commit, one element for an ordinary
  commit, two or more for a merge commit). `message` and `author` are strings.

  Serialization is deterministic: identical `tree_hash`, `parents` (in the same
  order), `message`, and `author` always yield the same commit hash, and any
  difference — including different parents — yields a different hash.
  """
  @spec commit(server(), hash(), [hash()], String.t(), String.t()) :: {:ok, hash()}
  def commit(server, tree_hash, parents, message, author)
      when is_binary(tree_hash) and is_list(parents) and is_binary(message) and
             is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parents, message, author})
  end

  @doc """
  Returns `{:ok, entries}` describing every commit reachable from `commit_hash`
  by transitively following parent links, or `{:error, :not_found}` if the
  starting hash is unknown.

  Each entry is a map with `:hash`, `:tree`, `:parents`, `:author`, and
  `:message`. The list is ordered newest-to-oldest: the starting commit is
  first and every commit appears before all of its ancestors (a
  reverse-topological ordering).
  """
  @spec log(server(), hash()) :: {:ok, [entry()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

  @doc """
  Returns `{:ok, base_hash}` where `base_hash` is a lowest common ancestor of
  `hash_a` and `hash_b`.

  A commit counts as an ancestor of itself. The returned base is an ancestor of
  both commits that is not a proper ancestor of any other common ancestor.
  Returns `{:error, :not_found}` if either hash is unknown, or
  `{:error, :no_merge_base}` if the commits share no common ancestor.
  """
  @spec merge_base(server(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found | :no_merge_base}
  def merge_base(server, hash_a, hash_b)
      when is_binary(hash_a) and is_binary(hash_b) do
    GenServer.call(server, {:merge_base, hash_a, hash_b})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(_arg) do
    {:ok, %{objects: %{}}}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = sha1_hex(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree, parents, message, author}, _from, state) do
    object = build_commit_object(tree, parents, message, author)
    hash = sha1_hex(object)
    objects = Map.put_new(state.objects, hash, object)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:log, hash}, _from, state) do
    {:reply, do_log(state.objects, hash), state}
  end

  def handle_call({:merge_base, a, b}, _from, state) do
    {:reply, do_merge_base(state.objects, a, b), state}
  end

  # ------------------------------------------------------------------
  # Hashing
  # ------------------------------------------------------------------

  # TODO: @spec
  defp sha1_hex(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  # ------------------------------------------------------------------
  # Commit serialization / parsing
  # ------------------------------------------------------------------

  # A commit is serialized as a deterministic, git-like text representation:
  #
  #     tree <tree-hash>
  #     parent <parent-hash>        (repeated, once per parent, in order)
  #     author <byte-size>
  #     <author>
  #     message <byte-size>
  #     <message>
  #
  # The byte-size headers let the author and message round-trip verbatim even
  # when they contain newlines. Identical inputs always yield identical bytes —
  # and therefore an identical hash — while any difference in the tree, in the
  # parents (including their order), in the author, or in the message changes
  # the bytes and thus the hash.
  @spec build_commit_object(hash(), [hash()], String.t(), String.t()) :: binary()
  defp build_commit_object(tree_hash, parents, message, author) do
    IO.iodata_to_binary([
      "tree ",
      tree_hash,
      "\n",
      Enum.map(parents, fn parent -> ["parent ", parent, "\n"] end),
      "author ",
      Integer.to_string(byte_size(author)),
      "\n",
      author,
      "\n",
      "message ",
      Integer.to_string(byte_size(message)),
      "\n",
      message,
      "\n"
    ])
  end

  @spec parse_commit(binary()) :: %{
          tree: hash(),
          parents: [hash()],
          author: String.t(),
          message: String.t()
        }
  defp parse_commit(binary) do
    {"tree " <> tree, rest} = split_line(binary)
    {parents, rest} = parse_parents(rest, [])
    {"author " <> author_size, rest} = split_line(rest)
    author_bytes = String.to_integer(author_size)
    <<author::binary-size(^author_bytes), "\n", rest::binary>> = rest
    {"message " <> message_size, rest} = split_line(rest)
    message_bytes = String.to_integer(message_size)
    <<message::binary-size(^message_bytes), "\n">> = rest

    %{tree: tree, parents: parents, author: author, message: message}
  end

  @spec parse_parents(binary(), [hash()]) :: {[hash()], binary()}
  defp parse_parents("parent " <> _ = binary, acc) do
    {"parent " <> parent, rest} = split_line(binary)
    parse_parents(rest, [parent | acc])
  end

  defp parse_parents(binary, acc), do: {Enum.reverse(acc), binary}

  @spec split_line(binary()) :: {binary(), binary()}
  defp split_line(binary) do
    [line, rest] = :binary.split(binary, "\n")
    {line, rest}
  end

  # ------------------------------------------------------------------
  # log/2 implementation
  # ------------------------------------------------------------------

  @spec do_log(map(), hash()) :: {:ok, [entry()]} | {:error, :not_found}
  defp do_log(objects, start) do
    if Map.has_key?(objects, start) do
      {order, _visited} = dfs_post(start, objects, [], MapSet.new())
      {:ok, Enum.map(order, &entry(&1, objects))}
    else
      {:error, :not_found}
    end
  end

  @spec dfs_post(hash(), map(), [hash()], MapSet.t()) :: {[hash()], MapSet.t()}
  defp dfs_post(node, objects, acc, visited) do
    if MapSet.member?(visited, node) do
      {acc, visited}
    else
      visited = MapSet.put(visited, node)
      %{parents: parents} = parse_commit(Map.fetch!(objects, node))

      {acc, visited} =
        Enum.reduce(parents, {acc, visited}, fn parent, {inner_acc, inner_visited} ->
          dfs_post(parent, objects, inner_acc, inner_visited)
        end)

      {[node | acc], visited}
    end
  end

  @spec entry(hash(), map()) :: entry()
  defp entry(hash, objects) do
    %{parents: parents, tree: tree, author: author, message: message} =
      parse_commit(Map.fetch!(objects, hash))

    %{
      hash: hash,
      tree: tree,
      parents: parents,
      author: author,
      message: message
    }
  end

  # ------------------------------------------------------------------
  # merge_base/3 implementation
  # ------------------------------------------------------------------

  @spec do_merge_base(map(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found | :no_merge_base}
  defp do_merge_base(objects, a, b) do
    cond do
      not Map.has_key?(objects, a) ->
        {:error, :not_found}

      not Map.has_key?(objects, b) ->
        {:error, :not_found}

      true ->
        common = MapSet.intersection(ancestors(objects, a), ancestors(objects, b))

        case objects |> lowest_common(common) |> MapSet.to_list() |> Enum.sort() do
          [] -> {:error, :no_merge_base}
          [base | _] -> {:ok, base}
        end
    end
  end

  @spec lowest_common(map(), MapSet.t()) :: MapSet.t()
  defp lowest_common(objects, common) do
    proper =
      Enum.reduce(common, MapSet.new(), fn node, acc ->
        node_ancestors =
          objects
          |> ancestors(node)
          |> MapSet.delete(node)

        MapSet.union(acc, MapSet.intersection(node_ancestors, common))
      end)

    MapSet.difference(common, proper)
  end

  @spec ancestors(map(), hash()) :: MapSet.t()
  defp ancestors(objects, start) do
    ancestors_walk([start], objects, MapSet.new())
  end

  @spec ancestors_walk([hash()], map(), MapSet.t()) :: MapSet.t()
  defp ancestors_walk([], _objects, visited), do: visited

  defp ancestors_walk([node | rest], objects, visited) do
    if MapSet.member?(visited, node) do
      ancestors_walk(rest, objects, visited)
    else
      visited = MapSet.put(visited, node)
      %{parents: parents} = parse_commit(Map.fetch!(objects, node))
      ancestors_walk(parents ++ rest, objects, visited)
    end
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
