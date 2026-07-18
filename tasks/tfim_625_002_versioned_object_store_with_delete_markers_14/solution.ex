  test "get_object_version preserves per-version metadata", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"tag" => "a"})
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two", %{"tag" => "b"})

    assert {:ok, %{metadata: %{"tag" => "a"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v1)

    assert {:ok, %{metadata: %{"tag" => "b"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v2)
  end