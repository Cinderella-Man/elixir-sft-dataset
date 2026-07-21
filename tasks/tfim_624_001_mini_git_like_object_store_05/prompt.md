# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp walk_log(_state, nil, acc), do: {:ok, Enum.reverse(acc)}

  defp walk_log(state, hash, acc) do
    case Map.fetch(state, hash) do
      :error when acc == [] ->
        {:error, :not_found}

      :error ->
        # Dangling parent reference — stop gracefully.
        {:ok, Enum.reverse(acc)}

      {:ok, content} ->
        parsed = parse_commit(content)

        entry = %{
          hash: hash,
          tree: parsed.tree,
          parent: parsed.parent,
          author: parsed.author,
          message: parsed.message
        }

        walk_log(state, parsed.parent, [entry | acc])
    end
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ObjectStore.start_link([])
    %{store: pid}
  end

  # -------------------------------------------------------
  # Helper — compute expected SHA-1 for a given binary
  # -------------------------------------------------------

  defp sha1(content) do
    :crypto.hash(:sha, content) |> Base.encode16(case: :lower)
  end

  # -------------------------------------------------------
  # Basic store / retrieve
  # -------------------------------------------------------

  test "store returns the SHA-1 hash of the content", %{store: s} do
    content = "hello world"
    {:ok, hash} = ObjectStore.store(s, content)

    assert hash == sha1(content)
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

  # -------------------------------------------------------
  # Content-addressability (deduplication)
  # -------------------------------------------------------

  test "storing the same content twice returns the same hash", %{store: s} do
    # TODO
  end

  test "different content produces different hashes", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "aaa")
    {:ok, h2} = ObjectStore.store(s, "bbb")

    assert h1 != h2
  end

  # -------------------------------------------------------
  # Tree objects
  # -------------------------------------------------------

  test "tree stores a tree object and returns its hash", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "file content")

    entries = [%{name: "README.md", hash: blob_hash, type: :blob}]
    {:ok, tree_hash} = ObjectStore.tree(s, entries)

    assert tree_hash =~ ~r/^[0-9a-f]{40}$/
    # The tree object itself should be retrievable as raw content
    assert {:ok, _raw} = ObjectStore.retrieve(s, tree_hash)
  end

  test "tree hash is deterministic regardless of entry order", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "content a")
    {:ok, h2} = ObjectStore.store(s, "content b")

    entries_asc = [
      %{name: "a.txt", hash: h1, type: :blob},
      %{name: "b.txt", hash: h2, type: :blob}
    ]

    entries_desc = [
      %{name: "b.txt", hash: h2, type: :blob},
      %{name: "a.txt", hash: h1, type: :blob}
    ]

    {:ok, tree1} = ObjectStore.tree(s, entries_asc)
    {:ok, tree2} = ObjectStore.tree(s, entries_desc)

    assert tree1 == tree2
  end

  test "trees with different entries produce different hashes", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "x")
    {:ok, h2} = ObjectStore.store(s, "y")

    {:ok, t1} = ObjectStore.tree(s, [%{name: "file", hash: h1, type: :blob}])
    {:ok, t2} = ObjectStore.tree(s, [%{name: "file", hash: h2, type: :blob}])

    assert t1 != t2
  end

  test "trees differing only in entry type produce different hashes", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "same target object")

    {:ok, as_blob} = ObjectStore.tree(s, [%{name: "thing", hash: blob_hash, type: :blob}])
    {:ok, as_tree} = ObjectStore.tree(s, [%{name: "thing", hash: blob_hash, type: :tree}])

    assert as_blob != as_tree
  end

  test "trees differing only in entry name produce different hashes", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "same target object")

    {:ok, t1} = ObjectStore.tree(s, [%{name: "a.txt", hash: blob_hash, type: :blob}])
    {:ok, t2} = ObjectStore.tree(s, [%{name: "b.txt", hash: blob_hash, type: :blob}])

    assert t1 != t2
  end

  test "multi-entry trees differing only in one entry's type differ", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "first target")
    {:ok, h2} = ObjectStore.store(s, "second target")

    {:ok, t1} =
      ObjectStore.tree(s, [
        %{name: "a", hash: h1, type: :blob},
        %{name: "b", hash: h2, type: :blob}
      ])

    {:ok, t2} =
      ObjectStore.tree(s, [
        %{name: "a", hash: h1, type: :blob},
        %{name: "b", hash: h2, type: :tree}
      ])

    assert t1 != t2
  end

  test "tree can contain nested tree references", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "nested content")

    {:ok, subtree_hash} =
      ObjectStore.tree(s, [%{name: "inner.txt", hash: blob_hash, type: :blob}])

    entries = [
      %{name: "subdir", hash: subtree_hash, type: :tree},
      %{name: "root.txt", hash: blob_hash, type: :blob}
    ]

    {:ok, root_tree_hash} = ObjectStore.tree(s, entries)
    assert root_tree_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, root_tree_hash)
  end

  # -------------------------------------------------------
  # Commit objects
  # -------------------------------------------------------

  test "commit creates a commit object and returns its hash", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "v1")
    {:ok, tree_hash} = ObjectStore.tree(s, [%{name: "file.txt", hash: blob_hash, type: :blob}])

    {:ok, commit_hash} = ObjectStore.commit(s, tree_hash, nil, "initial commit", "alice")

    assert commit_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, commit_hash)
  end

  test "commit with a parent references the parent hash", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "v1")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f.txt", hash: bh, type: :blob}])
    {:ok, c1} = ObjectStore.commit(s, th, nil, "first", "alice")

    {:ok, bh2} = ObjectStore.store(s, "v2")
    {:ok, th2} = ObjectStore.tree(s, [%{name: "f.txt", hash: bh2, type: :blob}])
    {:ok, c2} = ObjectStore.commit(s, th2, c1, "second", "bob")

    assert c1 != c2
  end

  test "same commit metadata produces the same hash (deterministic)", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    {:ok, c1} = ObjectStore.commit(s, th, nil, "msg", "author")
    {:ok, c2} = ObjectStore.commit(s, th, nil, "msg", "author")

    assert c1 == c2
  end

  # -------------------------------------------------------
  # Log (walking the parent chain)
  # -------------------------------------------------------

  test "log of a single root commit returns one entry", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])
    {:ok, ch} = ObjectStore.commit(s, th, nil, "root commit", "alice")

    {:ok, entries} = ObjectStore.log(s, ch)

    assert length(entries) == 1
    [entry] = entries
    assert entry.hash == ch
    assert entry.message == "root commit"
    assert entry.author == "alice"
    assert entry.tree == th
    assert entry.parent == nil
  end

  test "log walks a chain of three commits newest-to-oldest", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "v1")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    {:ok, c1} = ObjectStore.commit(s, th, nil, "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, th, c1, "second", "bob")
    {:ok, c3} = ObjectStore.commit(s, th, c2, "third", "carol")

    {:ok, log} = ObjectStore.log(s, c3)

    assert length(log) == 3
    assert Enum.map(log, & &1.message) == ["third", "second", "first"]
    assert Enum.map(log, & &1.author) == ["carol", "bob", "alice"]
    assert Enum.map(log, & &1.hash) == [c3, c2, c1]

    # Parent chain integrity
    assert Enum.at(log, 0).parent == c2
    assert Enum.at(log, 1).parent == c1
    assert Enum.at(log, 2).parent == nil
  end

  test "log returns error for unknown commit hash", %{store: s} do
    assert {:error, :not_found} = ObjectStore.log(s, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "store and retrieve empty content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "")
    assert {:ok, ""} = ObjectStore.retrieve(s, hash)
    assert hash == sha1("")
  end

  test "store and retrieve binary content with null bytes", %{store: s} do
    content = <<0, 1, 2, 255, 254, 253>>
    {:ok, hash} = ObjectStore.store(s, content)
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end

  test "tree with empty entries list", %{store: s} do
    {:ok, tree_hash} = ObjectStore.tree(s, [])
    assert tree_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, tree_hash)
  end

  test "commit messages can contain newlines and special characters", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    message = "fix: handle edge case\n\nThis fixes a bug where\nnull bytes caused issues."
    {:ok, ch} = ObjectStore.commit(s, th, nil, message, "dev <dev@example.com>")

    {:ok, [entry]} = ObjectStore.log(s, ch)
    assert entry.message == message
    assert entry.author == "dev <dev@example.com>"
  end

  # -------------------------------------------------------
  # Integration: full workflow
  # -------------------------------------------------------

  test "full workflow: blobs → trees → commits → log", %{store: s} do
    # Store some file contents
    {:ok, readme_hash} = ObjectStore.store(s, "# My Project\n")
    {:ok, license_hash} = ObjectStore.store(s, "MIT License\n")
    {:ok, code_hash} = ObjectStore.store(s, "defmodule App do\nend\n")

    # Build a subtree for lib/
    {:ok, lib_tree} =
      ObjectStore.tree(s, [
        %{name: "app.ex", hash: code_hash, type: :blob}
      ])

    # Build the root tree
    {:ok, root_tree} =
      ObjectStore.tree(s, [
        %{name: "README.md", hash: readme_hash, type: :blob},
        %{name: "LICENSE", hash: license_hash, type: :blob},
        %{name: "lib", hash: lib_tree, type: :tree}
      ])

    # Initial commit
    {:ok, c1} = ObjectStore.commit(s, root_tree, nil, "Initial commit", "alice")

    # Modify a file and create a second commit
    {:ok, readme_v2} = ObjectStore.store(s, "# My Project\n\nUpdated readme.\n")

    {:ok, root_tree_v2} =
      ObjectStore.tree(s, [
        %{name: "README.md", hash: readme_v2, type: :blob},
        %{name: "LICENSE", hash: license_hash, type: :blob},
        %{name: "lib", hash: lib_tree, type: :tree}
      ])

    {:ok, c2} = ObjectStore.commit(s, root_tree_v2, c1, "Update README", "bob")

    # Walk the log
    {:ok, log} = ObjectStore.log(s, c2)

    assert length(log) == 2
    assert Enum.at(log, 0).message == "Update README"
    assert Enum.at(log, 0).tree == root_tree_v2
    assert Enum.at(log, 1).message == "Initial commit"
    assert Enum.at(log, 1).tree == root_tree

    # Every object is still individually retrievable
    assert {:ok, "# My Project\n"} = ObjectStore.retrieve(s, readme_hash)
    assert {:ok, "# My Project\n\nUpdated readme.\n"} = ObjectStore.retrieve(s, readme_v2)
    assert {:ok, _} = ObjectStore.retrieve(s, lib_tree)
    assert {:ok, _} = ObjectStore.retrieve(s, root_tree)
    assert {:ok, _} = ObjectStore.retrieve(s, root_tree_v2)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
  end

  # -------------------------------------------------------
  # Process registration via the :name option
  # -------------------------------------------------------

  defp unique_name(prefix) do
    :"#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  test "start_link registers the process under the given :name" do
    name = unique_name("object_store_registered")
    {:ok, pid} = ObjectStore.start_link(name: name)

    assert Process.whereis(name) == pid
  end

  test "the whole public API can be driven through the registered name" do
    name = unique_name("object_store_by_name")
    {:ok, _pid} = ObjectStore.start_link(name: name)

    {:ok, blob} = ObjectStore.store(name, "named blob")
    assert {:ok, "named blob"} = ObjectStore.retrieve(name, blob)

    {:ok, tree} = ObjectStore.tree(name, [%{name: "f.txt", hash: blob, type: :blob}])
    {:ok, root} = ObjectStore.commit(name, tree, nil, "first", "alice")
    {:ok, head} = ObjectStore.commit(name, tree, root, "second", "bob")

    {:ok, log} = ObjectStore.log(name, head)
    assert Enum.map(log, & &1.hash) == [head, root]
    assert Enum.map(log, & &1.message) == ["second", "first"]

    assert {:error, :not_found} =
             ObjectStore.retrieve(name, "1111111111111111111111111111111111111111")
  end

  test "each named store keeps its own independent object map" do
    name_a = unique_name("object_store_a")
    name_b = unique_name("object_store_b")
    {:ok, _a} = ObjectStore.start_link(name: name_a)
    {:ok, _b} = ObjectStore.start_link(name: name_b)

    {:ok, hash} = ObjectStore.store(name_a, "only in a")

    assert {:ok, "only in a"} = ObjectStore.retrieve(name_a, hash)
    assert {:error, :not_found} = ObjectStore.retrieve(name_b, hash)
  end
end
```
