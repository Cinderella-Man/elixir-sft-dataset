  test "a per-object ttl overrides the server default_ttl_ms", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end