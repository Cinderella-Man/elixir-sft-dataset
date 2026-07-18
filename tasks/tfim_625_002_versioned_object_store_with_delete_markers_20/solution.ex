  test "delete_version is idempotent", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "never", "nope")
  end