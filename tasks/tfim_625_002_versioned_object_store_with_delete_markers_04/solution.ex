  test "list_buckets is empty for a fresh store", %{os: os} do
    assert {:ok, []} = VersionedObjectStorage.list_buckets(os)
  end