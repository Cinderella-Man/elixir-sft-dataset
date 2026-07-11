  test "put overwrites an existing object silently", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v1")
    ObjectStorage.put_object(os, "b", "k", "v2")

    assert {:ok, %{data: "v2"}} = ObjectStorage.get_object(os, "b", "k")
  end