  test "handles mixed maps containing lists of maps", %{m: m} do
    data = %{
      page: 1,
      results: [
        %{name: "Alice", credit_card: "4111111111111234"},
        %{name: "Bob", credit_card: "5500005555555559"}
      ]
    }

    result = LogMasker.mask(m, data)
    assert result.page == 1
    [r1, r2] = result.results
    assert r1.name == "Alice"
    assert r1.credit_card == "[MASKED]"
    assert r2.name == "Bob"
    assert r2.credit_card == "[MASKED]"
  end