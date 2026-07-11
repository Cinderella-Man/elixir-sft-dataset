  test "list_versions is ordered strictly newest first", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, v3} = VersionedObjectStorage.put_object(os, "b", "k", "three")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert Enum.map(versions, & &1.version_id) == [v3, v2, v1]
  end