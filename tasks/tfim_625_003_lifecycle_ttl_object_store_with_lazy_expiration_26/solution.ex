  test "server default_ttl_ms applies when no per-object ttl is given", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v")
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end