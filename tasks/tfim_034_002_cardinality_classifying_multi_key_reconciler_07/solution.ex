  test "key fields are never reported as differences by default" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 2}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{a: %{left: 1, right: 9}}
  end