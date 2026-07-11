  test "delete a non-empty bucket returns error", %{os: os} do
    ObjectStorage.create_bucket(os, "full")
    ObjectStorage.put_object(os, "full", "file.txt", "hello")
    assert {:error, :not_empty} = ObjectStorage.delete_bucket(os, "full")
  end