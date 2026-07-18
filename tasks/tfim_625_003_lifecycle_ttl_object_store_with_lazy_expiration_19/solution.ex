  test "set_ttl extends the life of an object", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end