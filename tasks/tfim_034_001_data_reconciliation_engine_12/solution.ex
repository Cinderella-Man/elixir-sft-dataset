  test "compare_fields restricts which fields are diffed" do
    left = [%{id: 1, name: "Alice", internal_ref: "old"}]
    right = [%{id: 1, name: "Alice", internal_ref: "new"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    # :internal_ref differs but is excluded from comparison
    assert entry.differences == %{}
  end