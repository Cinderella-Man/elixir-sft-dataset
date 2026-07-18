  test "get on a key with no versions returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "missing")
  end