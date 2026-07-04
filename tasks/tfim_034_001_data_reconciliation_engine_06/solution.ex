  test "empty left list" do
    left = []
    right = [%{id: 1}, %{id: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_left == []
    assert length(result.only_in_right) == 2
  end