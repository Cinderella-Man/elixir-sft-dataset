    test "applies a rule to a field of each element in a list" do
      records = [%{orders: [%{card: "1111"}, %{card: "2222"}]}]
      [r] = Anonymizer.anonymize(records, %{"orders[].card" => :redact})
      assert Enum.map(r.orders, & &1.card) == ["[REDACTED]", "[REDACTED]"]
    end