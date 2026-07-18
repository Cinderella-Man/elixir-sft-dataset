  test "bucket names with hyphens, dots and digits are accepted", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "my-bucket.v2")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "a.b-c9")
    assert {:ok, ["a.b-c9", "my-bucket.v2"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "has_underscore")
  end