  test "list_objects with prefix filter", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "images/cat.png", "")
    ObjectStorage.put_object(os, "b", "images/dog.png", "")
    ObjectStorage.put_object(os, "b", "docs/readme.md", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", prefix: "images/")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["images/cat.png", "images/dog.png"]
  end