  test "copy fails when source key doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.copy_object(os, "b", "missing", "b", "dst")
  end