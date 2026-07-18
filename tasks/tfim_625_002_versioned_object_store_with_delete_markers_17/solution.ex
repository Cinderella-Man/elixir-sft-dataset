  test "delete marker still hides the object after re-put then re-delete", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 4
  end