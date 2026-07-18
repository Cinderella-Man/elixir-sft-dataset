  test "a record missing a key field is keyed as nil and matches an explicit nil key" do
    config = config!(key_fields: [:id])

    report = TolerantReconciler.run(config, [%{value: 7}], [%{id: nil, value: 7}])

    assert length(report.matched) == 1
    [entry] = report.matched
    assert entry.left == %{value: 7}
    assert entry.right == %{id: nil, value: 7}
    assert entry.differences == %{}
  end