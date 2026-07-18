  test "list_objects shows only live keys, sorted", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "a", "1")
    VersionedObjectStorage.put_object(os, "b", "b", "22")
    VersionedObjectStorage.put_object(os, "b", "c", "333")
    VersionedObjectStorage.delete_object(os, "b", "b")

    assert {:ok, objs} = VersionedObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "c"]

    assert Enum.all?(objs, fn o ->
             is_integer(o.size) and match?(%DateTime{}, o.last_modified)
           end)
  end