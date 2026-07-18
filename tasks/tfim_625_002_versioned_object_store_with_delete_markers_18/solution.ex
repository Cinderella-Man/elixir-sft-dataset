  test "delete_version permanently removes one version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)
    assert {:ok, [one]} = VersionedObjectStorage.list_versions(os, "b", "k")
    refute one.version_id == vid1
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end