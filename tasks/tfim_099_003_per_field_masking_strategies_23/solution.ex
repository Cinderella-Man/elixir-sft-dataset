  test "a differently-cased string policy key masks an atom data key" do
    m = FieldMasker.new(%{"PassWord" => :redact})
    result = FieldMasker.mask(m, %{password: "x"})
    assert result.password == "[MASKED]"
  end