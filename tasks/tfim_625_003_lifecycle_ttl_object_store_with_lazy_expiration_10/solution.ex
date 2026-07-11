  test "put and get an empty binary reports a zero size", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "")
    assert {:ok, %{data: "", size: 0}} = TtlObjectStorage.get_object(os, "b", "k")
  end