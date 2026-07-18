# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `merge_base` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store whose commit history is a **directed acyclic graph (DAG)** — commits may have any number of parents, including two or more for merge commits. This is the key difference from a plain linear-history store: `log` must walk a graph, not a single chain, and there is a `merge_base` operation for finding a common ancestor of two commits.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process. It should accept a `:name` option for process registration. Internal state is an in-memory map of SHA-1 hex digest → stored binary content.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), persists the raw content keyed by that hash, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not duplicate data.

- `ObjectStore.retrieve(server, hash)` which looks up a hash and returns `{:ok, content}` if found, or `{:error, :not_found}` if the hash does not exist.

- `ObjectStore.commit(server, tree_hash, parents, message, author)` which creates a commit object. `tree_hash` is a SHA-1 string of any already-stored object. `parents` is a **list** of parent commit hashes: use `[]` for a root commit, a single-element list for an ordinary commit, and a two-or-more-element list for a merge commit. `message` and `author` are strings. Build a deterministic text representation containing all fields, store it as an object, and return `{:ok, commit_hash}`. Serialization is deterministic: the same `tree_hash`, the same list of `parents` in the same order, the same `message`, and the same `author` always yield the same commit hash. Different parents produce a different hash.

- `ObjectStore.log(server, commit_hash)` which returns `{:ok, entries}` where `entries` is a list of maps describing every commit **reachable** from `commit_hash` by transitively following parent links (the starting commit and all of its ancestors). Each map contains `:hash`, `:tree`, `:parents` (the list of parent hashes), `:author`, and `:message`. The list is ordered newest-to-oldest: the starting commit is always the first element, and every commit appears **before** all of its ancestors (a reverse-topological ordering). If the starting hash is not found, return `{:error, :not_found}`.

- `ObjectStore.merge_base(server, hash_a, hash_b)` which returns `{:ok, base_hash}` where `base_hash` is a lowest common ancestor of the two commits — a commit that is an ancestor of both `hash_a` and `hash_b` and that is not itself a proper ancestor of any other common ancestor. A commit counts as an ancestor of itself. If either `hash_a` or `hash_b` is not found, return `{:error, :not_found}`. If the two commits share no common ancestor at all, return `{:error, :no_merge_base}`.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- All stored objects (blobs and commits) live in the same flat hash map — there is no type distinction at the storage layer.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `merge_base` missing

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
    # TODO
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

Give me only the complete implementation of `merge_base` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
