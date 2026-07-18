  test "get_object_version fetches a specific historical version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, v} = VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
    assert v.data == "one"
    assert v.version_id == vid1
    assert v.is_delete_marker == false
  end