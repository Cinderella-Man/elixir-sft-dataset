  test "many left and one right record produce a many_to_one entry" do
    left = [%{id: 7, v: 1}, %{id: 7, v: 2}]
    right = [%{id: 7, v: 3}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.many_to_one
    assert entry.key == %{id: 7}
    assert entry.left == [%{id: 7, v: 1}, %{id: 7, v: 2}]
    assert entry.right == %{id: 7, v: 3}
    assert report.one_to_one == []
    assert report.one_to_many == []
  end