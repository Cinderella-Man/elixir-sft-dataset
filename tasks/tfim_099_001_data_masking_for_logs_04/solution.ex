  test "leaves non-sensitive keys untouched", %{m: m} do
    data = %{user_id: 42, email: "alice@example.com", role: "admin"}
    result = LogMasker.mask(m, data)
    assert result.user_id == 42
    assert result.role == "admin"
  end