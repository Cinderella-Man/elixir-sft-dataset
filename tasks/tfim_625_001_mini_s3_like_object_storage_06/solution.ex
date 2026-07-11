  test "delete an empty bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "temp")
    assert :ok = ObjectStorage.delete_bucket(os, "temp")
    assert {:ok, []} = ObjectStorage.list_buckets(os)
  end