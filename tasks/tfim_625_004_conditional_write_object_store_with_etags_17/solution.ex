  test "list_objects on a missing bucket errors", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.list_objects(os, "nope")
  end