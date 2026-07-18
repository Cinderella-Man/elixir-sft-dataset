  test "a bucket name with a trailing newline is rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "abc\n")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a-b.c\n")
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end