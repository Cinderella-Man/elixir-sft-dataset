# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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
  @spec update_branch(GenServer.server(), String.t(), hash, hash) ::
          {:ok, hash} | {:error, :no_branch | :not_found | :conflict}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ObjectStore.start_link([])
    %{store: pid}
  end

  defp sha1(content), do: :crypto.hash(:sha, content) |> Base.encode16(case: :lower)

  # ---------------- store / retrieve / commit ----------------

  test "store returns lowercase SHA-1 and is idempotent", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "hi")
    {:ok, h2} = ObjectStore.store(s, "hi")
    assert h1 == sha1("hi")
    assert h1 == h2
  end

  test "store keeps distinct content under distinct hashes", %{store: s} do
    {:ok, ha} = ObjectStore.store(s, "alpha")
    {:ok, hb} = ObjectStore.store(s, "beta")
    assert ha != hb
    assert {:ok, "alpha"} = ObjectStore.retrieve(s, ha)
    assert {:ok, "beta"} = ObjectStore.retrieve(s, hb)
  end

  test "store handles binary content with null bytes", %{store: s} do
    payload = <<0, 1, 2, 255, 0>>
    {:ok, h} = ObjectStore.store(s, payload)
    assert h == sha1(payload)
    assert {:ok, ^payload} = ObjectStore.retrieve(s, h)
  end

  test "retrieve returns content or not_found", %{store: s} do
    {:ok, h} = ObjectStore.store(s, "data")
    assert {:ok, "data"} = ObjectStore.retrieve(s, h)
    assert {:error, :not_found} = ObjectStore.retrieve(s, sha1("nope"))
  end

  test "commit is deterministic", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "msg", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, nil, "msg", "alice")
    assert c1 == c2
  end

  test "commit differing arguments produce differing hashes", %{store: s} do
    # TODO
  end

  test "commit stores a retrievable object", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    assert {:ok, content} = ObjectStore.retrieve(s, c)
    assert is_binary(content)
    assert c == sha1(content)
  end

  # ---------------- branch creation / lookup ----------------

  test "create_branch and branch_head", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")

    assert {:ok, "main"} = ObjectStore.create_branch(s, "main", c)
    assert {:ok, ^c} = ObjectStore.branch_head(s, "main")
  end

  test "create_branch rejects a duplicate name", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)
    assert {:error, :exists} = ObjectStore.create_branch(s, "main", c)
  end

  test "create_branch rejects an unknown commit", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.create_branch(s, "main", sha1("ghost"))
  end

  test "create_branch can point a blob-backed branch at any stored object", %{store: s} do
    {:ok, blob} = ObjectStore.store(s, "loose")
    assert {:ok, "b"} = ObjectStore.create_branch(s, "b", blob)
    assert {:ok, ^blob} = ObjectStore.branch_head(s, "b")
  end

  test "branch_head returns no_branch for unknown branch", %{store: s} do
    assert {:error, :no_branch} = ObjectStore.branch_head(s, "missing")
  end

  # ---------------- update_branch (CAS) ----------------

  test "update_branch moves the branch on a matching expected hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, ^c2} = ObjectStore.update_branch(s, "main", c1, c2)
    assert {:ok, ^c2} = ObjectStore.branch_head(s, "main")
  end

  test "update_branch conflicts and leaves branch unchanged on stale expected hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:error, :conflict} = ObjectStore.update_branch(s, "main", c2, c2)
    assert {:ok, ^c1} = ObjectStore.branch_head(s, "main")
  end

  test "update_branch on unknown branch returns no_branch", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "one", "alice")
    assert {:error, :no_branch} = ObjectStore.update_branch(s, "missing", c, c)
  end

  test "update_branch with unknown new hash returns not_found", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    assert {:error, :not_found} = ObjectStore.update_branch(s, "main", c1, sha1("ghost"))
  end

  test "update_branch to the same hash is a no-op success", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    assert {:ok, ^c1} = ObjectStore.update_branch(s, "main", c1, c1)
    assert {:ok, ^c1} = ObjectStore.branch_head(s, "main")
  end

  # ---------------- delete_branch / list_branches ----------------

  test "delete_branch removes a branch", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)

    assert :ok = ObjectStore.delete_branch(s, "main")
    assert {:error, :no_branch} = ObjectStore.branch_head(s, "main")
    assert {:error, :no_branch} = ObjectStore.delete_branch(s, "main")
  end

  test "list_branches is empty for a fresh store", %{store: s} do
    assert ObjectStore.list_branches(s) == %{}
  end

  test "list_branches returns all branches", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "a", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, nil, "b", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, _} = ObjectStore.create_branch(s, "dev", c2)

    assert ObjectStore.list_branches(s) == %{"main" => c1, "dev" => c2}
  end

  test "list_branches reflects deletions", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)
    {:ok, _} = ObjectStore.create_branch(s, "dev", c)
    :ok = ObjectStore.delete_branch(s, "dev")

    assert ObjectStore.list_branches(s) == %{"main" => c}
  end

  # ---------------- garbage collection ----------------

  test "gc removes an unreferenced loose blob but keeps commit and tree", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, dangling} = ObjectStore.store(s, "dangling blob")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, dangling)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, "tree-content"} = ObjectStore.retrieve(s, tree)
  end

  test "gc on an empty store removes nothing", %{store: s} do
    assert {:ok, 0} = ObjectStore.gc(s)
  end

  test "gc is idempotent once nothing is unreachable", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, tree)
  end

  test "gc collects commits that became unreachable after a branch delete", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, ^c2} = ObjectStore.update_branch(s, "main", c1, c2)

    {:ok, orphan} = ObjectStore.commit(s, tree, nil, "independent root", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "tmp", orphan)
    :ok = ObjectStore.delete_branch(s, "tmp")

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, orphan)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
    assert {:ok, _} = ObjectStore.retrieve(s, tree)
    assert {:ok, ^c2} = ObjectStore.branch_head(s, "main")
  end

  test "gc keeps ancestors reachable through any branch", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, dangling} = ObjectStore.store(s, "junk")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)
    {:ok, _} = ObjectStore.create_branch(s, "old", c1)

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, dangling)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
  end

  test "gc keeps a tree shared by multiple reachable commits", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "shared-tree")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, "shared-tree"} = ObjectStore.retrieve(s, tree)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
  end

  test "gc sweeps everything when there are no branches", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, _c1} = ObjectStore.commit(s, tree, nil, "root", "alice")

    assert {:ok, 2} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, tree)
    assert ObjectStore.list_branches(s) == %{}
  end

  test "start_link registers the process under a given name", %{store: _s} do
    name = :object_store_named_test
    {:ok, _pid} = ObjectStore.start_link(name: name)

    {:ok, blob} = ObjectStore.store(name, "named-content")
    assert {:ok, "named-content"} = ObjectStore.retrieve(name, blob)
    assert ObjectStore.list_branches(name) == %{}
  end

  test "gc keeps a grandparent commit reachable only through a multi-hop parent chain", %{
    store: s
  } do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, c3} = ObjectStore.commit(s, tree, c2, "three", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c3)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
    assert {:ok, _} = ObjectStore.retrieve(s, c3)
  end

  test "gc keeps the distinct tree of an ancestor commit", %{store: s} do
    {:ok, tree1} = ObjectStore.store(s, "old-tree")
    {:ok, tree2} = ObjectStore.store(s, "new-tree")
    {:ok, c1} = ObjectStore.commit(s, tree1, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree2, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, "old-tree"} = ObjectStore.retrieve(s, tree1)
    assert {:ok, "new-tree"} = ObjectStore.retrieve(s, tree2)
  end

  test "gc sweeps the old commit and its tree after a branch moves to an unrelated root", %{
    store: s
  } do
    {:ok, tree1} = ObjectStore.store(s, "old-tree")
    {:ok, tree2} = ObjectStore.store(s, "new-tree")
    {:ok, c1} = ObjectStore.commit(s, tree1, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree2, nil, "unrelated root", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, ^c2} = ObjectStore.update_branch(s, "main", c1, c2)

    assert {:ok, 2} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, c1)
    assert {:error, :not_found} = ObjectStore.retrieve(s, tree1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
    assert {:ok, "new-tree"} = ObjectStore.retrieve(s, tree2)
  end

  test "gc keeps a blob that a branch points at directly", %{store: s} do
    {:ok, blob} = ObjectStore.store(s, "branch-target")
    {:ok, junk} = ObjectStore.store(s, "junk blob")
    {:ok, _} = ObjectStore.create_branch(s, "b", blob)

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:ok, "branch-target"} = ObjectStore.retrieve(s, blob)
    assert {:error, :not_found} = ObjectStore.retrieve(s, junk)
  end

  test "storing identical content twice leaves exactly one object for gc to sweep", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "dup")
    {:ok, h2} = ObjectStore.store(s, "dup")
    assert h1 == h2

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, h1)
  end
end
```
