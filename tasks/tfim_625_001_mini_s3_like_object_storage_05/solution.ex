  test "valid bucket names with hyphens and dots", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "my-bucket")
    assert :ok = ObjectStorage.create_bucket(os, "my.bucket.v2")
    assert :ok = ObjectStorage.create_bucket(os, "abc123")
  end