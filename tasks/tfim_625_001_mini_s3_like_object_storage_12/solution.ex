  test "get a non-existent key", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "missing")
  end