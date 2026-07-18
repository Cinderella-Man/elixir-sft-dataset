  test "bucket names with underscores or slashes are invalid, digits are valid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a_b")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a/b")
    assert :ok = TtlObjectStorage.create_bucket(os, "a1-b.2")
    assert {:ok, ["a1-b.2"]} = TtlObjectStorage.list_buckets(os)
  end