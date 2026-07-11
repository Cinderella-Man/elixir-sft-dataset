  test "list_buckets is empty for a fresh server", %{os: os} do
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end