  test "list_objects returns sorted entries with etag and size", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "c", "333")
    ConditionalObjectStorage.put_object(os, "b", "a", "1")
    ConditionalObjectStorage.put_object(os, "b", "b", "22")

    assert {:ok, objs} = ConditionalObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "b", "c"]
    a = Enum.find(objs, &(&1.key == "a"))
    assert a.size == 1
    assert a.etag == etag_of("1")
    assert %DateTime{} = a.last_modified
  end