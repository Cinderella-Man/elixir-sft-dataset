  test "list_objects on empty bucket returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "empty")
  end