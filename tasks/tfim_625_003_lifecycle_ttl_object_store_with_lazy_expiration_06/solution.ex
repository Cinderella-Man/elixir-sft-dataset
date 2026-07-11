  test "non-string bucket names are rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, :atom)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, 123)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "has space")
  end