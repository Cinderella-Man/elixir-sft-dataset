  test "list_objects returns all keys sorted", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "c.txt", "")
    ObjectStorage.put_object(os, "b", "a.txt", "")
    ObjectStorage.put_object(os, "b", "b.txt", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["a.txt", "b.txt", "c.txt"]
  end