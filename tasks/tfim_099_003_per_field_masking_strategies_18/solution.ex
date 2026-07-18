  test "mask_string masks a dashed credit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111-1111-1111-1234") == "****-****-****-1234"
  end