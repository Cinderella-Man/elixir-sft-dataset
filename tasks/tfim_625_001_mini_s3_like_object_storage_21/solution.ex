  test "list_objects with max_keys", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    for i <- 1..10,
        do: ObjectStorage.put_object(os, "b", "file-#{String.pad_leading("#{i}", 2, "0")}", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", max_keys: 3)
    assert length(objects) == 3
  end