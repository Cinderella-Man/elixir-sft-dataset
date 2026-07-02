  test "retrieve returns error for unknown hash", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.retrieve(s, "0000000000000000000000000000000000000000")
  end