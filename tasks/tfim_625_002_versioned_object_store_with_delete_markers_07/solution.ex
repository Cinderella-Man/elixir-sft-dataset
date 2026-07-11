  test "put returns a unique version id and get returns the latest version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")

    assert {:ok, vid} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"n" => "1"})
    assert is_binary(vid)

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.data == "one"
    assert obj.metadata == %{"n" => "1"}
    assert obj.size == byte_size("one")
    assert obj.version_id == vid
    assert %DateTime{} = obj.last_modified
  end