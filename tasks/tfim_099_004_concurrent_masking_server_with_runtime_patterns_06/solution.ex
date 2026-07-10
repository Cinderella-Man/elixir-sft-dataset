  test "leaves non-sensitive keys untouched", %{s: s} do
    result = MaskingServer.mask(s, %{count: 7, role: "admin"})
    assert result.count == 7
    assert result.role == "admin"
  end