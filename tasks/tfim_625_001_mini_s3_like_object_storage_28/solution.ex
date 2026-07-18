  test "copy fails when source bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "dst")

    assert {:error, :src_bucket_not_found} =
             ObjectStorage.copy_object(os, "ghost", "k", "dst", "k")
  end