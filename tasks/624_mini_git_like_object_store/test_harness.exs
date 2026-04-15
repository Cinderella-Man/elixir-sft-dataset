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
    {:ok, h1} = ObjectStore.store(s, "duplicate")
    {:ok, h2} = ObjectStore.store(s, "duplicate")

    assert h1 == h2
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
end
