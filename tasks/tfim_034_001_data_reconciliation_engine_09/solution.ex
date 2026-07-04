  test "identical matched records have empty differences map" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alice", age: 30}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
  end