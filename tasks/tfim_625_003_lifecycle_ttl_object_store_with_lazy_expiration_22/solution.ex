  test "set_ttl errors for missing bucket or key", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.set_ttl(os, "nope", "k", 100)
    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "missing", 100)
  end