  test "pattern-masks string values under non-sensitive keys", %{s: s} do
    result = MaskingServer.mask(s, %{note: "email john.doe@example.com"})
    assert result.note =~ "j***@example.com"
    refute result.note =~ "john.doe"
  end