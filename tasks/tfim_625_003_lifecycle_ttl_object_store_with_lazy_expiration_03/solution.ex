  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "UPPER")
    assert :ok = TtlObjectStorage.create_bucket(os, "a-b.c")
    assert {:error, :already_exists} = TtlObjectStorage.create_bucket(os, "a-b.c")
  end