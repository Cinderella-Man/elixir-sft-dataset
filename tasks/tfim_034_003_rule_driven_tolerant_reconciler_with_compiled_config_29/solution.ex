  test "case_insensitive rule falls back to equality for non-binaries" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report = TolerantReconciler.run(config, [%{id: 1, name: "x"}], [%{id: 1, name: nil}])

    [entry] = report.matched
    assert Map.has_key?(entry.differences, :name)
  end