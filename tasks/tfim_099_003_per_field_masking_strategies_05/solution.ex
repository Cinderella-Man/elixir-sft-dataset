  test "last4 fully masks a short string" do
    m = FieldMasker.new(%{pin: :last4})
    result = FieldMasker.mask(m, %{pin: "ab"})
    assert result.pin == "**"
  end