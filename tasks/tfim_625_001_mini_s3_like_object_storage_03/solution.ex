  test "creating a duplicate bucket returns error", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "photos")
    assert {:error, :already_exists} = ObjectStorage.create_bucket(os, "photos")
  end