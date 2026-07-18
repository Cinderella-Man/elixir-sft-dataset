  test "start_link registers the process under the given :name option" do
    name = :object_store_promise_named
    {:ok, pid} = ObjectStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid

    {:ok, hash} = ObjectStore.store(name, "named registration")
    assert hash == sha1("named registration")
    assert {:ok, "named registration"} = ObjectStore.retrieve(name, hash)
  end