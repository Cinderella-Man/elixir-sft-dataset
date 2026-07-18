  test "explicitly compared field absent from left record diffs as nil vs value" do
    left = [%{id: 1}]
    right = [%{id: 1, score: 7}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:score]
      )

    [entry] = result.matched
    assert entry.differences == %{score: %{left: nil, right: 7}}
  end