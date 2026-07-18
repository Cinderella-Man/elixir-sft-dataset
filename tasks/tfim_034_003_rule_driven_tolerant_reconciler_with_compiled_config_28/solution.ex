  test "case_insensitive rule still reports genuinely different strings" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "Bob"}])

    [entry] = report.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Bob", rule: :case_insensitive}
           }
  end