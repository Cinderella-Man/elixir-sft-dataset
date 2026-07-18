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