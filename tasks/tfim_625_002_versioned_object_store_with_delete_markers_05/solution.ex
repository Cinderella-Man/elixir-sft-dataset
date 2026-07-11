  test "underscore and slash bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad_name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad/name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "MiXeD")
  end