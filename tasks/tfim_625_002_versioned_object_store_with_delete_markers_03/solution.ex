  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "has space")
    assert :ok = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
    assert {:error, :already_exists} = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
  end