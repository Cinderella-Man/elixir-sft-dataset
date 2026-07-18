  test "a repeated key within one list keeps only the last record with that key" do
    config = config!(key_fields: [:id])

    left = [%{id: 1, name: "first"}, %{id: 1, name: "last"}]
    right = [%{id: 1, name: "last"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.left == %{id: 1, name: "last"}
    assert entry.differences == %{}
    assert report.only_in_left == []
    assert report.only_in_right == []
  end