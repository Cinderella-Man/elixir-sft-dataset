  test "set_ttl can shorten an object's life", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: :infinity)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end