  test "delete_object is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.delete_object(os, "nope", "k")
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "never")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end