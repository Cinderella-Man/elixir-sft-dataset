  test "copy an object across buckets", %{os: os} do
    ObjectStorage.create_bucket(os, "src-bucket")
    ObjectStorage.create_bucket(os, "dst-bucket")
    ObjectStorage.put_object(os, "src-bucket", "file", "cross-bucket", "image/png")

    assert :ok = ObjectStorage.copy_object(os, "src-bucket", "file", "dst-bucket", "file-copy")

    assert {:ok, %{data: "cross-bucket", content_type: "image/png"}} =
             ObjectStorage.get_object(os, "dst-bucket", "file-copy")
  end