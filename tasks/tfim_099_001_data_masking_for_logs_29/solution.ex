  test "mask/2 given a raw string returns a string with all patterns scrubbed", %{m: m} do
    input = "ssn 123-45-6789, card 4111-1111-1111-1234, mail john.doe@example.com"
    result = LogMasker.mask(m, input)
    assert is_binary(result)
    assert result =~ "***-**-****"
    assert result =~ "****-****-****-1234"
    assert result =~ "j***@example.com"
    refute result =~ "123-45-6789"
    refute result =~ "john.doe@example.com"
  end