  test "retrieve returns corrupt when the file cannot be decompressed", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "will be clobbered")
    File.write!(object_path(dir, hash), "this is not valid zlib data")
    assert {:error, :corrupt} = ObjectStore.retrieve(s, hash)
  end