  test "records only in right appear in :only_in_right" do
    left = [%{id: 1}]
    right = [%{id: 1}, %{id: 3}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_right == [%{id: 3}]
    assert result.only_in_left == []
    assert length(result.matched) == 1
  end