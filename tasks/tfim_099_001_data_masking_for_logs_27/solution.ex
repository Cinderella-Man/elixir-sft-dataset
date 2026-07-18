  test "two space-separated SSNs are both fully masked", %{m: m} do
    result = LogMasker.mask_string(m, "123-45-6789 987-65-4321")
    refute result =~ "4321"
    assert result == "***-**-**** ***-**-****"
  end