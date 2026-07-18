  test "get_object_version on unknown version returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "k", "one")
    assert {:error, :not_found} = VersionedObjectStorage.get_object_version(os, "b", "k", "bogus")
  end