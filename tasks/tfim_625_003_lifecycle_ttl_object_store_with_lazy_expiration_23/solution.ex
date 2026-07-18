  test "set_ttl on an already expired key errors as not_found", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
  end