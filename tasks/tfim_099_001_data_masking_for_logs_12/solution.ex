  test "masks credit card number (no separators)", %{m: m} do
    result = LogMasker.mask_string(m, "card: 4111111111111234 end")
    refute result =~ "411111111111"
    assert result =~ "1234"
  end