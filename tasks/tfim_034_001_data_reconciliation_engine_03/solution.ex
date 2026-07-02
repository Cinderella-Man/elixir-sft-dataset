  test "records only in left appear in :only_in_left" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == []
    assert length(result.matched) == 1
  end