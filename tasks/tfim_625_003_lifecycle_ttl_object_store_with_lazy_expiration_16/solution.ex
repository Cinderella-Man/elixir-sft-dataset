  test "purge_expired counts across multiple buckets", %{os: os} do
    TtlObjectStorage.create_bucket(os, "one")
    TtlObjectStorage.create_bucket(os, "two")
    :ok = TtlObjectStorage.put_object(os, "one", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "live", "v", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "one")
    assert {:ok, [%{key: "live"}]} = TtlObjectStorage.list_objects(os, "two")
  end