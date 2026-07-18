  test "list_objects includes size and last_modified", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "12345")

    assert {:ok, [obj]} = ObjectStorage.list_objects(os, "b")
    assert obj.key == "k"
    assert obj.size == 5
    assert %DateTime{} = obj.last_modified
  end