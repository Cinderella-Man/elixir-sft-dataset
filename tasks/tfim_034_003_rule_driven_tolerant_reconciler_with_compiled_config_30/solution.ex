  test "ignore rule keeps a field out of the differences map" do
    config = config!(key_fields: [:id], rules: [synced_at: :ignore])

    report =
      TolerantReconciler.run(
        config,
        [%{id: 1, synced_at: "t1", name: "Alice"}],
        [%{id: 1, synced_at: "t2", name: "Alice"}]
      )

    [entry] = report.matched
    assert entry.differences == %{}
  end