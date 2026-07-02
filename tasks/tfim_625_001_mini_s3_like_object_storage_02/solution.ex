  test "create and list buckets", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "alpha")
    assert :ok = ObjectStorage.create_bucket(os, "beta")
    assert {:ok, ["alpha", "beta"]} = ObjectStorage.list_buckets(os)
  end