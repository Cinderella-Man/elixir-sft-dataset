# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule CascadeCrud.ArchiveTest do
  use ExUnit.Case, async: false

  alias CascadeCrud.Archive

  setup do
    server = start_supervised!({Archive, []})
    %{server: server}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp folder!(server, name, parent_id \\ nil) do
    {:ok, folder} = Archive.create_folder(server, %{name: name, parent_id: parent_id})
    folder
  end

  defp file!(server, name, parent_id, content \\ "body") do
    {:ok, file} =
      Archive.create_file(server, %{name: name, parent_id: parent_id, content: content})

    file
  end

  defp archive!(server, id) do
    {:ok, result} = Archive.archive_node(server, id)
    result
  end

  # -------------------------------------------------------
  # Creation
  # -------------------------------------------------------

  describe "create_folder/2" do
    test "creates a root folder with sequential ids", %{server: s} do
      assert {:ok, a} = Archive.create_folder(s, %{name: "root"})
      assert a.id == 1
      assert a.type == :folder
      assert a.name == "root"
      assert a.parent_id == nil
      assert a.content == nil
      assert a.archived_at == nil
      assert a.archive_origin == nil

      assert {:ok, b} = Archive.create_folder(s, %{name: "other"})
      assert b.id == 2
    end

    test "creates a nested folder", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, child} = Archive.create_folder(s, %{name: "child", parent_id: root.id})
      assert child.parent_id == root.id
    end

    test "rejects invalid names", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_folder(s, %{})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: ""})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: "   "})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: :nope})
    end

    test "rejects a missing or non-folder parent", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "note.txt", root.id)

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: 999})

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: f.id})
    end

    test "rejects an archived parent", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_folder(s, %{name: "x", parent_id: root.id})
    end
  end

  describe "create_file/2" do
    test "creates a file inside a folder with default content", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, f} = Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
      assert f.type == :file
      assert f.content == ""
      assert f.parent_id == root.id
      assert f.archived_at == nil

      assert {:ok, g} =
               Archive.create_file(s, %{name: "b.txt", parent_id: root.id, content: "hello"})

      assert g.content == "hello"
    end

    test "requires a folder parent", %{server: s} do
      assert {:error, :parent_not_found} = Archive.create_file(s, %{name: "a.txt"})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: nil})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: 42})
    end

    test "rejects an archived parent folder", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
    end

    test "validates the name before the parent", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_file(s, %{name: "", parent_id: 999})
    end
  end

  # -------------------------------------------------------
  # Fetch / list
  # -------------------------------------------------------

  describe "fetch_node/3" do
    test "fetches a live node", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, fetched} = Archive.fetch_node(s, root.id)
      assert fetched.id == root.id
      assert fetched.name == "root"
    end

    test "returns :not_found for unknown ids", %{server: s} do
      assert {:error, :not_found} = Archive.fetch_node(s, 123)
    end

    test "hides archived nodes unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.fetch_node(s, root.id)
      assert {:ok, node} = Archive.fetch_node(s, root.id, include_archived: true)
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at
    end
  end

  describe "list_children/3" do
    test "returns direct children sorted by id, excluding archived by default", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      sub = folder!(s, "sub", root.id)
      b = file!(s, "b.txt", root.id)
      _deep = file!(s, "deep.txt", sub.id)

      archive!(s, a.id)

      assert {:ok, children} = Archive.list_children(s, root.id)
      assert Enum.map(children, & &1.id) == [sub.id, b.id]

      assert {:ok, all} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(all, & &1.id) == Enum.sort([a.id, sub.id, b.id])
    end

    test "empty folder yields an empty list", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, []} = Archive.list_children(s, root.id)
    end

    test "archived folder is hidden unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      child = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.list_children(s, root.id)

      assert {:ok, children} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(children, & &1.id) == [child.id]
    end

    test "returns :not_found for files and unknown ids", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:error, :not_found} = Archive.list_children(s, f.id)
      assert {:error, :not_found} = Archive.list_children(s, 999)
    end
  end

  # -------------------------------------------------------
  # Rename
  # -------------------------------------------------------

  describe "rename_node/3" do
    test "renames a live folder and file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, renamed} = Archive.rename_node(s, root.id, "archive")
      assert renamed.name == "archive"
      assert {:ok, again} = Archive.fetch_node(s, root.id)
      assert again.name == "archive"

      assert {:ok, rf} = Archive.rename_node(s, f.id, "b.txt")
      assert rf.name == "b.txt"
      assert rf.content == "body"
    end

    test "rejects invalid names", %{server: s} do
      root = folder!(s, "root")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "  ")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, 7)
    end

    test "cannot rename archived or unknown nodes", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.rename_node(s, root.id, "nope")
      assert {:error, :not_found} = Archive.rename_node(s, 999, "nope")
    end
  end

  # -------------------------------------------------------
  # Cascading archive
  # -------------------------------------------------------

  describe "archive_node/2" do
    test "archiving a file affects only that file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert node.id == f.id
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at

      assert {:ok, _} = Archive.fetch_node(s, root.id)
      assert {:error, :not_found} = Archive.fetch_node(s, f.id)
    end

    test "archiving a folder cascades to the whole subtree with one timestamp", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", root.id)
      b = file!(s, "b.txt", sub.id)

      assert {:ok, %{node: node, cascaded: cascaded}} = Archive.archive_node(s, root.id)
      assert node.archive_origin == :direct
      assert cascaded == Enum.sort([sub.id, a.id, b.id])

      for id <- cascaded do
        assert {:ok, n} = Archive.fetch_node(s, id, include_archived: true)
        assert n.archive_origin == :cascade
        assert n.archived_at == node.archived_at
        assert {:error, :not_found} = Archive.fetch_node(s, id)
      end
    end

    test "already-archived descendants are left untouched and not reported", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      %{node: sub_archived} = archive!(s, sub.id)
      assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)

      assert cascaded == [loose.id]

      assert {:ok, sub_now} = Archive.fetch_node(s, sub.id, include_archived: true)
      assert sub_now.archive_origin == :direct
      assert sub_now.archived_at == sub_archived.archived_at

      assert {:ok, deep_now} = Archive.fetch_node(s, deep.id, include_archived: true)
      assert deep_now.archive_origin == :cascade
    end

    test "errors for unknown and already-archived nodes", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :already_archived} = Archive.archive_node(s, root.id)
      assert {:error, :not_found} = Archive.archive_node(s, 999)
    end
  end

  # -------------------------------------------------------
  # Archive timestamp shape
  # -------------------------------------------------------

  describe "archived_at shape" do
    test "the returned target timestamp is UTC and truncated to the second", %{server: s} do
      root = folder!(s, "root")

      assert {:ok, %{node: node}} = Archive.archive_node(s, root.id)
      assert %DateTime{} = ts = node.archived_at

      # UTC zone: no offset from UTC, and the UTC zone name.
      assert ts.time_zone == "Etc/UTC"
      assert ts.utc_offset == 0
      assert ts.std_offset == 0

      # Second precision: no sub-second component survives truncation.
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts
    end

    test "stored timestamps on target and cascade are UTC second-precision", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      leaf = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      for id <- [root.id, sub.id, leaf.id] do
        assert {:ok, stored} = Archive.fetch_node(s, id, include_archived: true)
        assert %DateTime{} = ts = stored.archived_at
        assert ts.time_zone == "Etc/UTC"
        assert ts.utc_offset == 0
        assert ts.std_offset == 0
        assert ts.microsecond == {0, 0}
        assert DateTime.truncate(ts, :second) == ts
      end
    end

    test "a directly archived file also carries a UTC second-precision stamp", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert %DateTime{} = ts = node.archived_at
      assert ts.time_zone == "Etc/UTC"
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts

      assert {:ok, listed} = Archive.list_archived(s)
      assert [only] = listed
      assert only.id == f.id
      assert only.archived_at == ts
    end
  end

  # -------------------------------------------------------
  # Origin-aware restore
  # -------------------------------------------------------

  describe "unarchive_node/2" do
    test "restores a directly archived node and its cascade", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      assert {:ok, %{node: node, restored: restored}} = Archive.unarchive_node(s, root.id)
      assert node.archived_at == nil
      assert node.archive_origin == nil
      assert restored == Enum.sort([sub.id, a.id])

      for id <- [root.id, sub.id, a.id] do
        assert {:ok, n} = Archive.fetch_node(s, id)
        assert n.archived_at == nil
        assert n.archive_origin == nil
      end

      assert {:ok, []} = Archive.list_archived(s)
    end

    test "a directly archived child stays archived when the parent is restored", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
      assert restored == [loose.id]

      assert {:ok, _} = Archive.fetch_node(s, loose.id)
      assert {:error, :not_found} = Archive.fetch_node(s, sub.id)
      assert {:error, :not_found} = Archive.fetch_node(s, deep.id)

      assert {:ok, archived} = Archive.list_archived(s)
      assert Enum.map(archived, & &1.id) == Enum.sort([sub.id, deep.id])
    end

    test "a cascade-archived node cannot be restored on its own", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :cascade_archived} = Archive.unarchive_node(s, a.id)
      assert {:error, :not_found} = Archive.fetch_node(s, a.id)
    end

    test "cannot restore while the parent is still archived", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:error, :parent_archived} = Archive.unarchive_node(s, sub.id)

      assert {:ok, _} = Archive.unarchive_node(s, root.id)
      assert {:ok, %{node: node}} = Archive.unarchive_node(s, sub.id)
      assert node.archived_at == nil
    end

    test "errors for live and unknown nodes", %{server: s} do
      root = folder!(s, "root")

      assert {:error, :not_archived} = Archive.unarchive_node(s, root.id)
      assert {:error, :not_found} = Archive.unarchive_node(s, 999)
    end
  end

  # -------------------------------------------------------
  # Archived listing
  # -------------------------------------------------------

  describe "list_archived/1" do
    test "starts empty and lists every archived node sorted by id", %{server: s} do
      assert {:ok, []} = Archive.list_archived(s)

      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", sub.id)
      keep = folder!(s, "keep")

      archive!(s, root.id)

      assert {:ok, archived} = Archive.list_archived(s)
      assert Enum.map(archived, & &1.id) == Enum.sort([root.id, sub.id, a.id])
      refute keep.id in Enum.map(archived, & &1.id)

      origins = Map.new(archived, &{&1.id, &1.archive_origin})
      assert origins[root.id] == :direct
      assert origins[sub.id] == :cascade
      assert origins[a.id] == :cascade
    end
  end

  # -------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "build → archive → hidden → restore → visible → re-archive", %{server: s} do
      root = folder!(s, "projects")
      sub = folder!(s, "2026", root.id)
      note = file!(s, "notes.md", sub.id, "v1")

      assert {:ok, renamed} = Archive.rename_node(s, note.id, "notes.txt")
      assert renamed.name == "notes.txt"

      assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)
      assert cascaded == Enum.sort([sub.id, note.id])
      assert {:error, :not_found} = Archive.fetch_node(s, note.id)
      assert {:error, :parent_archived} = Archive.create_file(s, %{name: "x", parent_id: sub.id})

      assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
      assert restored == Enum.sort([sub.id, note.id])
      assert {:ok, back} = Archive.fetch_node(s, note.id)
      assert back.name == "notes.txt"
      assert back.content == "v1"

      assert {:ok, %{cascaded: again}} = Archive.archive_node(s, sub.id)
      assert again == [note.id]
      assert {:ok, children} = Archive.list_children(s, root.id)
      assert children == []
    end

    test "ids are never reused across archive and restore", %{server: s} do
      a = folder!(s, "a")
      archive!(s, a.id)
      b = folder!(s, "b")
      assert b.id == a.id + 1

      assert {:ok, _} = Archive.unarchive_node(s, a.id)
      c = folder!(s, "c")
      assert c.id == b.id + 1
    end
  end

  test "restore walks through a cascade child but skips a direct grandchild subtree", %{server: s} do
    root = folder!(s, "root")
    mid = folder!(s, "mid", root.id)
    leaf = folder!(s, "leaf", mid.id)
    deep = file!(s, "deep.txt", leaf.id)

    %{node: leaf_archived} = archive!(s, leaf.id)
    assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)
    assert cascaded == [mid.id]

    assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
    assert restored == [mid.id]

    assert {:ok, _} = Archive.fetch_node(s, mid.id)
    assert {:error, :not_found} = Archive.fetch_node(s, leaf.id)

    assert {:ok, leaf_now} = Archive.fetch_node(s, leaf.id, include_archived: true)
    assert leaf_now.archive_origin == :direct
    assert leaf_now.archived_at == leaf_archived.archived_at

    assert {:ok, deep_now} = Archive.fetch_node(s, deep.id, include_archived: true)
    assert deep_now.archive_origin == :cascade

    assert {:ok, %{restored: leaf_restored}} = Archive.unarchive_node(s, leaf.id)
    assert leaf_restored == [deep.id]
    assert {:ok, []} = Archive.list_archived(s)
  end

  test "start_link registers the server under the given :name and serves calls through it" do
    name = :"cascade_archive_named_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = Archive.start_link(name: name)
    assert Process.whereis(name) == pid

    assert {:ok, folder} = Archive.create_folder(name, %{name: "root"})
    assert folder.id == 1
    assert {:ok, ^folder} = Archive.fetch_node(name, folder.id)

    assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(name, folder.id)
    assert node.archive_origin == :direct
    assert {:ok, [archived]} = Archive.list_archived(name)
    assert archived.id == folder.id
  end

  test "rename_node reports :invalid_name before the node lookup", %{server: s} do
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, "")
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, "   ")
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, :nope)

    root = folder!(s, "root")
    archive!(s, root.id)
    assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "  ")
  end

  test "archiving a cascade-archived descendant reports :already_archived and restamps nothing",
       %{
         server: s
       } do
    root = folder!(s, "root")
    sub = folder!(s, "sub", root.id)
    f = file!(s, "a.txt", sub.id)

    %{node: target} = archive!(s, root.id)

    assert {:error, :already_archived} = Archive.archive_node(s, sub.id)
    assert {:error, :already_archived} = Archive.archive_node(s, f.id)

    for id <- [sub.id, f.id] do
      assert {:ok, n} = Archive.fetch_node(s, id, include_archived: true)
      assert n.archive_origin == :cascade
      assert n.archived_at == target.archived_at
    end
  end

  test "an archived file used as a parent yields :parent_not_found", %{server: s} do
    root = folder!(s, "root")
    f = file!(s, "a.txt", root.id)
    archive!(s, f.id)

    assert {:error, :parent_not_found} =
             Archive.create_file(s, %{name: "b.txt", parent_id: f.id})

    assert {:error, :parent_not_found} =
             Archive.create_folder(s, %{name: "sub", parent_id: f.id})
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
