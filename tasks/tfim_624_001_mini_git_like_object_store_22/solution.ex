  test "start_link registers the process under the given :name" do
    name = unique_name("object_store_registered")
    {:ok, pid} = ObjectStore.start_link(name: name)

    assert Process.whereis(name) == pid
  end