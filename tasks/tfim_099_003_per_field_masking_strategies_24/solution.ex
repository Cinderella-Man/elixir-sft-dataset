  test "mask_string masks a bare 13-digit card and a space-separated 19-digit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111111111234") == "*********1234"
    # 19 digits: only the final four digits (1, 2, 3, 4) survive, separators kept intact.
    assert FieldMasker.mask_string(m, "4111 1111 1111 1111 234") == "**** **** **** ***1 234"
  end