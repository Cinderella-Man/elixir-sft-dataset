  test "get from non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.get_object(os, "nope", "k")
  end