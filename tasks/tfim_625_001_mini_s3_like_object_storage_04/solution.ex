  test "invalid bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "has space")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "under_score")
  end