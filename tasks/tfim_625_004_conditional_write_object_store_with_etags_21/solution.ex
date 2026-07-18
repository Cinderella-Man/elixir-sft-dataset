  test "an empty bucket name is rejected as invalid_name", %{os: os} do
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "")
    assert {:ok, []} = ConditionalObjectStorage.list_buckets(os)
  end