  test "version operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.get_object_version(os, "nope", "k", "vid")

    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.delete_version(os, "nope", "k", "vid")
  end