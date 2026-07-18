  test "masks credit card number with dashes", %{m: m} do
    result = LogMasker.mask_string(m, "4111-1111-1111-1234")
    assert result == "****-****-****-1234"
  end