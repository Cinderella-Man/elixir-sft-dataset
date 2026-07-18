  test "list_objects reports bucket_not_found and empty buckets", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.list_objects(os, "nope")
    TtlObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "b")
  end