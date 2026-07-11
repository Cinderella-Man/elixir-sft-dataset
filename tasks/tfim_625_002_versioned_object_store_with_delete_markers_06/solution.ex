  test "buckets are isolated from one another", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "one")
    VersionedObjectStorage.create_bucket(os, "two")
    VersionedObjectStorage.put_object(os, "one", "k", "in-one")

    assert {:ok, %{data: "in-one"}} = VersionedObjectStorage.get_object(os, "one", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "two", "k")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "two")
  end