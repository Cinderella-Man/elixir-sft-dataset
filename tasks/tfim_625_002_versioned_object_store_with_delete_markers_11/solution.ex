  test "list_versions on a key with no versions returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = VersionedObjectStorage.list_versions(os, "b", "ghost")
  end