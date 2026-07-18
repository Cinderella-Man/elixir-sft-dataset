  test "stores and retrieves raw binary data correctly", %{os: os} do
    ObjectStorage.create_bucket(os, "bin")
    blob = :crypto.strong_rand_bytes(4096)
    ObjectStorage.put_object(os, "bin", "random.bin", blob, "application/octet-stream")

    assert {:ok, %{data: ^blob, size: 4096}} = ObjectStorage.get_object(os, "bin", "random.bin")
  end