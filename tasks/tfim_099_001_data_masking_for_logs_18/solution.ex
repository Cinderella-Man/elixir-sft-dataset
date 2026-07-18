  test "single-char local part email is handled without crashing", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com")
    assert result =~ "@b.com"
  end