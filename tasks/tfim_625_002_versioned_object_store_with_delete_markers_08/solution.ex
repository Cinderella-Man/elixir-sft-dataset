  test "put_object defaults metadata to an empty map", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _vid} = VersionedObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.metadata == %{}
    assert obj.data == "payload"
  end