  test "plain lists of maps and keyword lists are walked element-by-element" do
    m = FieldMasker.new(%{password: :redact})
    data = [%{password: "a"}, [password: "b"], "ping x@example.com"]
    result = FieldMasker.mask(m, data)
    assert [%{password: "[MASKED]"}, [password: "[MASKED]"], "ping x***@example.com"] = result
  end