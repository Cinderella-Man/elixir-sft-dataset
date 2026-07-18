  test "start_link registers the process under the given :name", %{dir: dir} do
    name = :"objstore_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = ObjectStore.start_link(dir: Path.join(dir, "named"), name: name)
    assert Process.whereis(name) == pid

    {:ok, hash} = ObjectStore.store(name, "via name")
    assert {:ok, "via name"} = ObjectStore.retrieve(name, hash)
    assert ObjectStore.has_object?(name, hash) == true
    assert ObjectStore.list_objects(name) == [hash]

    :ok = GenServer.stop(name)
  end