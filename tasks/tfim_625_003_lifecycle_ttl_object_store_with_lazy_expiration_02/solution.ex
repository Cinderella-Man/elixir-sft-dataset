  test "create, list, and delete buckets", %{os: os} do
    assert :ok = TtlObjectStorage.create_bucket(os, "beta")
    assert :ok = TtlObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = TtlObjectStorage.list_buckets(os)
    assert :ok = TtlObjectStorage.delete_bucket(os, "alpha")
    assert {:ok, ["beta"]} = TtlObjectStorage.list_buckets(os)
  end