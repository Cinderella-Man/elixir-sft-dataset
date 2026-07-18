  test "values equal under == are not reported as differences" do
    left = [%{id: 1, score: 1, ratio: 2.0}]
    right = [%{id: 1, score: 1.0, ratio: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
  end