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
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, base} = ObjectStore.commit(s, t, nil, "msg", "alice")
    {:ok, other_msg} = ObjectStore.commit(s, t, nil, "different", "alice")
    {:ok, other_author} = ObjectStore.commit(s, t, nil, "msg", "bob")
    assert base != other_msg
    assert base != other_author
    assert other_msg != other_author
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
