  test "hash strategy is stable across calls" do
    m = FieldMasker.new(%{password: :hash})
    a = FieldMasker.mask(m, %{password: "same"})
    b = FieldMasker.mask(m, %{password: "same"})
    assert a.password == b.password
  end