  test "last 4 digits of credit card are preserved", %{m: m} do
    result = LogMasker.mask_string(m, "5500005555555559")
    assert String.ends_with?(result, "5559")
    refute result =~ "550000"
  end