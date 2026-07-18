  test "masks email local part keeping first char", %{m: m} do
    result = LogMasker.mask_string(m, "Contact john.doe@example.com please")
    assert result =~ "j***@example.com"
    refute result =~ "john.doe"
  end