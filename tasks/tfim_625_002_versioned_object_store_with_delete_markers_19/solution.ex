  test "delete_version of an old version leaves it unreadable afterward", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)

    assert {:error, :not_found} =
             VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
  end