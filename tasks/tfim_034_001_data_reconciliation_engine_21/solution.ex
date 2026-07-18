  test "matched entry keeps full records when compare_fields excludes differing fields" do
    left = [%{id: 1, name: "Alice", internal_ref: "old", extra: 1}]
    right = [%{id: 1, name: "Alice", internal_ref: "new", extra: 2}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{}
    assert entry.left == %{id: 1, name: "Alice", internal_ref: "old", extra: 1}
    assert entry.right == %{id: 1, name: "Alice", internal_ref: "new", extra: 2}
  end