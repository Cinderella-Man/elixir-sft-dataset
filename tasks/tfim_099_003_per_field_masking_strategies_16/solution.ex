  test "policy keys match case-insensitively for string keys" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{"Password" => "x", "PASSWORD" => "y"})
    assert result["Password"] == "[MASKED]"
    assert result["PASSWORD"] == "[MASKED]"
  end