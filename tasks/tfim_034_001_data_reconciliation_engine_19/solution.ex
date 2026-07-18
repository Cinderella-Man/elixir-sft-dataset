  test "compare_fields field absent from both records yields no difference" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name, :nowhere_field]
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end