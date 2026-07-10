  test "applies pattern masking to string values on non-sensitive keys", %{m: m} do
    data = %{message: "User ssn is 123-45-6789, email: foo@bar.com"}
    result = LogMasker.mask(m, data)
    refute result.message =~ "123-45-6789"
    refute result.message =~ "foo@bar.com"
  end