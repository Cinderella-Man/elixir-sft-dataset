  test "masks multiple pattern types in one string", %{m: m} do
    input = "email: user@test.com, ssn: 000-11-2222, card: 4111-1111-1111-9999"
    result = LogMasker.mask_string(m, input)
    refute result =~ "user@test.com"
    refute result =~ "000-11-2222"
    refute result =~ "4111-1111-1111"
    assert result =~ "9999"
  end