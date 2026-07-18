  test "composite key with equal first field but differing second field never matches" do
    left = [%{org_id: 1, user_id: 10, name: "Alice"}]
    right = [%{org_id: 1, user_id: 11, name: "Alice"}]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert result.matched == []
    assert result.only_in_left == [%{org_id: 1, user_id: 10, name: "Alice"}]
    assert result.only_in_right == [%{org_id: 1, user_id: 11, name: "Alice"}]
  end