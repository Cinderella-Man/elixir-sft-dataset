  test "fields with no rule default to :exact and report the rule used" do
    config = config!(key_fields: [:id])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "Alicia"}])

    [entry] = report.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia", rule: :exact}}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == %{id: 1, name: "Alicia"}
  end