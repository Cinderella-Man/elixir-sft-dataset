  test "list_objects on empty bucket returns empty list", %{os: os} do
    ObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = ObjectStorage.list_objects(os, "empty")
  end