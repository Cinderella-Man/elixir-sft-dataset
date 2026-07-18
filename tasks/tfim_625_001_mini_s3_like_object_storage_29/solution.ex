  test "copy fails when destination bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "src")
    ObjectStorage.put_object(os, "src", "k", "v")

    assert {:error, :dst_bucket_not_found} =
             ObjectStorage.copy_object(os, "src", "k", "ghost", "k")
  end