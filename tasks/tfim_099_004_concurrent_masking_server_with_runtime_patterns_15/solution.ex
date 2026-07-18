  test "fresh server reports zero stats", %{s: s} do
    assert MaskingServer.stats(s) == %{keys_masked: 0, patterns_applied: 0}
  end