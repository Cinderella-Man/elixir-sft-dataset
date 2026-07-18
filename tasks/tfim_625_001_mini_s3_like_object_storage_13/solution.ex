  test "put to non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.put_object(os, "nope", "k", "v")
  end