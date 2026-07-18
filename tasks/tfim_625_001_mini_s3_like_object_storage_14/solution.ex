  test "default content_type is application/octet-stream", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "data")

    assert {:ok, %{content_type: "application/octet-stream"}} =
             ObjectStorage.get_object(os, "b", "k")
  end