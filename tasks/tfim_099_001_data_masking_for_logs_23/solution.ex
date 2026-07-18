  test "empty string returns empty string", %{m: m} do
    assert LogMasker.mask_string(m, "") == ""
  end