  test "set_ttl to infinity keeps a previously expiring object alive", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", :infinity)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end