  test "put to a missing bucket returns bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.put_object(os, "nope", "k", "v")
  end