  test "overwriting an object resets its ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "old", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "k", "new", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "new"}} = TtlObjectStorage.get_object(os, "b", "k")
  end