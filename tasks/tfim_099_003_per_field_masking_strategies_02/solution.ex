  test "redact strategy blanks the value" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{password: "hunter2", user: "alice"})
    assert result.password == "[MASKED]"
    assert result.user == "alice"
  end