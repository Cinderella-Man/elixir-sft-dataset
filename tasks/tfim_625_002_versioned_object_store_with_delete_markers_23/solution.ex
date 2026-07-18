  test "list_objects reports the latest version id per key", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, latest} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, [%{key: "k", version_id: ^latest, size: 3}]} =
             VersionedObjectStorage.list_objects(os, "b")
  end