  test "masks SSN pattern", %{m: m} do
    result = LogMasker.mask_string(m, "SSN: 123-45-6789 on file")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end