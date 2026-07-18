  test "start_link registers the process under a given name", %{store: _s} do
    name = :object_store_named_test
    {:ok, _pid} = ObjectStore.start_link(name: name)

    {:ok, blob} = ObjectStore.store(name, "named-content")
    assert {:ok, "named-content"} = ObjectStore.retrieve(name, blob)
    assert ObjectStore.list_branches(name) == %{}
  end