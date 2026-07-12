  test "keys absent from the other side are grouped under only_in_left / only_in_right" do
    left = [%{id: 1}, %{id: 2, tag: "a"}, %{id: 2, tag: "b"}]
    right = [%{id: 3}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert length(report.only_in_left) == 2
    assert length(report.only_in_right) == 1

    dup = Enum.find(report.only_in_left, &(&1.key == %{id: 2}))
    assert dup.records == [%{id: 2, tag: "a"}, %{id: 2, tag: "b"}]

    [only_right] = report.only_in_right
    assert only_right.key == %{id: 3}
    assert only_right.records == [%{id: 3}]
  end