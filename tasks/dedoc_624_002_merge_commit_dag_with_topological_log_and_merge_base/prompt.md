# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ObjectStore do
  use GenServer

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  def start_link(opts) do
    gen_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  def commit(server, tree_hash, parents, message, author)
      when is_binary(tree_hash) and is_list(parents) and is_binary(message) and
             is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parents, message, author})
  end

  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

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

  defp parse_parents("parent " <> _ = binary, acc) do
    {"parent " <> parent, rest} = split_line(binary)
    parse_parents(rest, [parent | acc])
  end

  defp parse_parents(binary, acc), do: {Enum.reverse(acc), binary}

  defp split_line(binary) do
    [line, rest] = :binary.split(binary, "\n")
    {line, rest}
  end

  # ------------------------------------------------------------------
  # log/2 implementation
  # ------------------------------------------------------------------

  defp do_log(objects, start) do
    if Map.has_key?(objects, start) do
      {order, _visited} = dfs_post(start, objects, [], MapSet.new())
      {:ok, Enum.map(order, &entry(&1, objects))}
    else
      {:error, :not_found}
    end
  end

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

  defp ancestors(objects, start) do
    ancestors_walk([start], objects, MapSet.new())
  end

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
