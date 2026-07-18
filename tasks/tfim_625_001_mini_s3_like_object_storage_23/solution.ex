  test "list_objects on non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.list_objects(os, "nope")
  end