  test "compare_fields still diffs the specified fields" do
    left = [%{id: 1, name: "Alice", score: 10}]
    right = [%{id: 1, name: "Bob", score: 10}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Bob"}}
  end