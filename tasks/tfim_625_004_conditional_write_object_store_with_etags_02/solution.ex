  test "create, list, invalid and duplicate buckets", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "beta")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "UP")
    assert {:error, :already_exists} = ConditionalObjectStorage.create_bucket(os, "alpha")
  end