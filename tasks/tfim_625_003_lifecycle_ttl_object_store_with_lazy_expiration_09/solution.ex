  test "an object with a live ttl is still readable", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end