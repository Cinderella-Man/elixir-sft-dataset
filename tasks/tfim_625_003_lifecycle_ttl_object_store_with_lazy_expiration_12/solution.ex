  test "reading an expired object removes it lazily", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    # The lazy read should have deleted it, so a later purge finds nothing.
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
  end