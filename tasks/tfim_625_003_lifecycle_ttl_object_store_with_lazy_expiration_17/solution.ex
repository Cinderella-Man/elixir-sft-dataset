  test "purge_expired returns zero when nothing has expired", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "k"}]} = TtlObjectStorage.list_objects(os, "b")
  end