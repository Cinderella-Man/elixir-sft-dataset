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