  test "masks multiple SSNs in one string", %{m: m} do
    result = LogMasker.mask_string(m, "123-45-6789 and 987-65-4321")
    assert result == "***-**-**** and ***-**-****"
  end