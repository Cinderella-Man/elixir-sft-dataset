  test "operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = VersionedObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.get_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.delete_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_versions(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_objects(os, "nope")
  end