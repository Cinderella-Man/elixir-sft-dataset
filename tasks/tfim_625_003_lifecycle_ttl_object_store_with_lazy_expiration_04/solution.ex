  test "delete_bucket returns not_found / not_empty", %{os: os} do
    assert {:error, :not_found} = TtlObjectStorage.delete_bucket(os, "ghost")

    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert {:error, :not_empty} = TtlObjectStorage.delete_bucket(os, "b")
  end