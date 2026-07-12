  test "a compared field missing from one record diffs as nil" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end