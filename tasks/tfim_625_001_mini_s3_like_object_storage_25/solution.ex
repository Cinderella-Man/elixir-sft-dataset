  test "copy an object within the same bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "src", "payload", "text/plain", %{"tag" => "1"})

    assert :ok = ObjectStorage.copy_object(os, "b", "src", "b", "dst")

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "dst")
    assert obj.data == "payload"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"tag" => "1"}

    # Source still exists
    assert {:ok, _} = ObjectStorage.get_object(os, "b", "src")
  end