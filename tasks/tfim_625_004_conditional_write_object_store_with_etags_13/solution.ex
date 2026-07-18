  test "delete is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.delete_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "never")
  end