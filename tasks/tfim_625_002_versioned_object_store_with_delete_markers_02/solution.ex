  test "create and list buckets sorted", %{os: os} do
    assert :ok = VersionedObjectStorage.create_bucket(os, "beta")
    assert :ok = VersionedObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = VersionedObjectStorage.list_buckets(os)
  end