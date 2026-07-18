  test "a repeated key on the right side also keeps only the last record" do
    config = config!(key_fields: [:id])

    left = [%{id: 1, name: "last"}]
    right = [%{id: 1, name: "first"}, %{id: 1, name: "last"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.right == %{id: 1, name: "last"}
    assert entry.differences == %{}
  end