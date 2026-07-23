# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

  @spec sha1_hex(binary()) :: hash()
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ObjectStore.start_link([])
    %{store: pid}
  end

  defp sha1(content) do
    :crypto.hash(:sha, content) |> Base.encode16(case: :lower)
  end

  defp order_ok?(entries) do
    index =
      entries
      |> Enum.with_index()
      |> Map.new(fn {e, i} -> {e.hash, i} end)

    Enum.all?(entries, fn e ->
      Enum.all?(e.parents, fn p -> Map.get(index, p) > Map.get(index, e.hash) end)
    end)
  end

  # ---------------- store / retrieve ----------------

  test "store returns the lowercase SHA-1 hash of the content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert byte_size(hash) == 40
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end

  test "retrieve returns content that was stored", %{store: s} do
    content = "some binary data \x00\x01\x02"
    {:ok, hash} = ObjectStore.store(s, content)
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns error for unknown hash", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.retrieve(s, "0000000000000000000000000000000000000000")
  end

  test "storing the same content twice returns the same hash", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "duplicate")
    {:ok, h2} = ObjectStore.store(s, "duplicate")
    assert h1 == h2
  end

  # ---------------- commit objects ----------------

  test "root commit (empty parents) is retrievable and has empty parents in log", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "root commit", "alice")

    assert c =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, c)

    {:ok, [entry]} = ObjectStore.log(s, c)
    assert entry.hash == c
    assert entry.tree == t
    assert entry.parents == []
    assert entry.message == "root commit"
    assert entry.author == "alice"
  end

  test "identical commit arguments produce the same hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "msg", "author")
    {:ok, c2} = ObjectStore.commit(s, t, [], "msg", "author")
    assert c1 == c2
  end

  test "different parents produce different commit hashes", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, base} = ObjectStore.commit(s, t, [], "base", "alice")
    {:ok, extra} = ObjectStore.commit(s, t, [], "extra", "alice")

    {:ok, one_parent} = ObjectStore.commit(s, t, [base], "x", "alice")
    {:ok, two_parents} = ObjectStore.commit(s, t, [base, extra], "x", "alice")
    assert one_parent != two_parents
  end

  # ---------------- log (DAG walk) ----------------

  test "log walks a linear chain newest-to-oldest", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")
    {:ok, c3} = ObjectStore.commit(s, t, [c2], "third", "carol")

    {:ok, log} = ObjectStore.log(s, c3)
    assert length(log) == 3
    assert hd(log).hash == c3
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([c1, c2, c3])
  end

  test "log of a merge commit includes both branches and orders ancestors after", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "branch a root", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [], "branch b root", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [c1, c2], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    assert length(log) == 3
    assert hd(log).hash == m
    assert hd(log).parents == [c1, c2]
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([m, c1, c2])
  end

  test "log returns error for unknown commit hash", %{store: s} do
    assert {:error, :not_found} = ObjectStore.log(s, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end

  # ---------------- merge_base ----------------

  test "merge_base of a diamond returns the shared root", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")

    assert {:ok, ^root} = ObjectStore.merge_base(s, a, b)
  end

  test "merge_base where one commit is an ancestor of the other", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c1} = ObjectStore.merge_base(s, c2, c1)
  end

  test "merge_base returns not_found when a hash is missing", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")

    assert {:error, :not_found} =
             ObjectStore.merge_base(s, c1, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end

  test "merge_base of two independent roots has no common ancestor", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, r1} = ObjectStore.commit(s, t, [], "root one", "alice")
    {:ok, r2} = ObjectStore.commit(s, t, [], "root two", "bob")

    assert {:error, :no_merge_base} = ObjectStore.merge_base(s, r1, r2)
  end

  test "merge_base returns the nearest shared ancestor, not an older common one", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, mid} = ObjectStore.commit(s, t, [root], "mid", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [mid], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [mid], "b", "bob")

    # root is also a common ancestor, but it is a proper ancestor of mid.
    assert {:ok, ^mid} = ObjectStore.merge_base(s, a, b)
  end

  test "the stored commit object is a text representation carrying every field", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "an important message", "alice")
    {:ok, raw} = ObjectStore.retrieve(s, c)

    assert String.printable?(raw)
    assert raw =~ t
    assert raw =~ "an important message"
    assert raw =~ "alice"
  end

  test "log of a diamond lists each reachable commit exactly once", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [a, b], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    hashes = Enum.map(log, & &1.hash)

    assert length(hashes) == 4
    assert Enum.uniq(hashes) == hashes
    assert MapSet.new(hashes) == MapSet.new([m, a, b, root])
    assert hd(log).hash == m
    assert order_ok?(log)
  end

  test "start_link registers the process under the given :name option" do
    # TODO
  end

  test "reordering the parent list changes the commit hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, p1} = ObjectStore.commit(s, t, [], "p one", "alice")
    {:ok, p2} = ObjectStore.commit(s, t, [], "p two", "bob")

    {:ok, ab} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")
    {:ok, ba} = ObjectStore.commit(s, t, [p2, p1], "merge", "carol")
    {:ok, again} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")

    assert ab != ba
    assert ab == again

    {:ok, [entry | _]} = ObjectStore.log(s, ba)
    assert entry.parents == [p2, p1]
  end

  test "merge_base of a commit with itself returns that commit", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c2} = ObjectStore.merge_base(s, c2, c2)
  end
end
```
