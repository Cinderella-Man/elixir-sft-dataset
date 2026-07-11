  test "put to a missing bucket and get errors", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = TtlObjectStorage.get_object(os, "nope", "k")

    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "missing")
  end