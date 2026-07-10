  test "handles deeply nested structures", %{m: m} do
    data = %{a: %{b: %{c: %{password: "deep"}}}}
    result = LogMasker.mask(m, data)
    assert result.a.b.c.password == "[MASKED]"
  end