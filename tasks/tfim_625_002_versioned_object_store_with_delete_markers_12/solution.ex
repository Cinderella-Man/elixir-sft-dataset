  test "each version records its own size", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, small} = VersionedObjectStorage.put_object(os, "b", "k", "hi")
    {:ok, big} = VersionedObjectStorage.put_object(os, "b", "k", "hello world")

    assert {:ok, sv} = VersionedObjectStorage.get_object_version(os, "b", "k", small)
    assert {:ok, bv} = VersionedObjectStorage.get_object_version(os, "b", "k", big)
    assert sv.size == byte_size("hi")
    assert bv.size == byte_size("hello world")
  end