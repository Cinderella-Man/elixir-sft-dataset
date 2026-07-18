  test "delete_bucket succeeds when only expired objects remain", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert :ok = TtlObjectStorage.delete_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end