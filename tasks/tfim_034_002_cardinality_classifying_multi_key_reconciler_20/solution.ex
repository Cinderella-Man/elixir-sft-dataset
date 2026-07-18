  test "mixed scenario" do
    left = [
      %{id: 1, name: "Alice", status: "active"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 2, name: "Bobby", status: "active"},
      %{id: 3, name: "Charlie", status: "inactive"}
    ]

    right = [
      %{id: 1, name: "Alice", status: "suspended"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 4, name: "Diana", status: "active"}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [alice] = report.one_to_one
    assert alice.key == %{id: 1}
    assert alice.differences == %{status: %{left: "active", right: "suspended"}}

    [bobs] = report.many_to_one
    assert length(bobs.left) == 2
    assert bobs.right.name == "Bob"

    [charlie] = report.only_in_left
    assert charlie.records == [%{id: 3, name: "Charlie", status: "inactive"}]

    [diana] = report.only_in_right
    assert diana.key == %{id: 4}

    counts = MultiKeyReconciler.counts(report)
    assert counts.ambiguous == 1
  end