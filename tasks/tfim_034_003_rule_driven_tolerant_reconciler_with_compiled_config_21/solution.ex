  test "identical records produce an empty differences map" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [%{id: 1, a: 1}], [%{id: 1, a: 1}])

    [entry] = report.matched
    assert entry.differences == %{}
  end