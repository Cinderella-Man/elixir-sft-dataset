  test "unique keys on both sides yield one_to_one entries" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert length(report.one_to_one) == 2
    assert report.one_to_many == []
    assert report.many_to_one == []
    assert report.many_to_many == []
    assert report.only_in_left == []
    assert report.only_in_right == []
  end