  test "deleting the delete marker restores the previous version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end