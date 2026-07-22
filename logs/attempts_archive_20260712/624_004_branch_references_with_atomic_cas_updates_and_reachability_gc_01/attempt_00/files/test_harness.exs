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

  # ---------------- delete_branch / list_branches ----------------

  test "delete_branch removes a branch", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)

    assert :ok = ObjectStore.delete_branch(s, "main")
    assert {:error, :no_branch} = ObjectStore.branch_head(s, "main")
    assert {:error, :no_branch} = ObjectStore.delete_branch(s, "main")
  end

  test "list_branches returns all branches", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "a", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, nil, "b", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, _} = ObjectStore.create_branch(s, "dev", c2)

    assert ObjectStore.list_branches(s) == %{"main" => c1, "dev" => c2}
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
end
