  test "case_insensitive rule ignores case and surrounding whitespace" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "  alice "}])

    [entry] = report.matched
    assert entry.differences == %{}
  end