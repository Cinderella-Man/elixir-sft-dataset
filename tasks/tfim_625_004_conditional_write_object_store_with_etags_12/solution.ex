  test "get errors for missing bucket and missing key", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.get_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "missing")
  end