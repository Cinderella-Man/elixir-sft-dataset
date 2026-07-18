  test "start_link registers the process under the given name option" do
    name = :cos_named_registration_test
    {:ok, pid} = ConditionalObjectStorage.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid
    assert :ok = ConditionalObjectStorage.create_bucket(name, "b")
    assert {:ok, ["b"]} = ConditionalObjectStorage.list_buckets(name)
  end