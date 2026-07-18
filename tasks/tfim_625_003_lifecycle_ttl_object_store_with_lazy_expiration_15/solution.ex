  test "purge_expired removes expired objects and reports the count", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "a", "x", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "b", "y", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "c", "z", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "c"}]} = TtlObjectStorage.list_objects(os, "b")
  end