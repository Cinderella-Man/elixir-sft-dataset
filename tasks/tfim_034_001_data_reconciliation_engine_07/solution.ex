  test "empty right list" do
    left = [%{id: 1}, %{id: 2}]
    right = []

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_right == []
    assert length(result.only_in_left) == 2
  end