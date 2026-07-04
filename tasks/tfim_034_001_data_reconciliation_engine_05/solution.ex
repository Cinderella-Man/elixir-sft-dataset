  test "completely disjoint lists produce no matches" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 3}, %{id: 4}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert length(result.only_in_left) == 2
    assert length(result.only_in_right) == 2
  end