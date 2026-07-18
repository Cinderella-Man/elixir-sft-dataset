  test "composite key matches only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      # same user_id, different org
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert length(result.matched) == 1
    [entry] = result.matched
    assert entry.left.name == "Alice"

    # Bob (org 1, user 20)
    assert length(result.only_in_left) == 1
    # Charlie (org 2, user 10)
    assert length(result.only_in_right) == 1
  end