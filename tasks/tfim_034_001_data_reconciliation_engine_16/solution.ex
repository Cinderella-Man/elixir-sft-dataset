  test "a field missing from one record is diffed as nil vs present value" do
    left = [%{id: 1, score: 42}]
    # :score absent
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end