  test "empty and null-byte content round-trip", %{store: s} do
    {:ok, he} = ObjectStore.store(s, "")
    assert {:ok, ""} = ObjectStore.retrieve(s, he)

    bin = <<0, 1, 2, 255, 254, 253>>
    {:ok, hb} = ObjectStore.store(s, bin)
    assert {:ok, ^bin} = ObjectStore.retrieve(s, hb)
  end