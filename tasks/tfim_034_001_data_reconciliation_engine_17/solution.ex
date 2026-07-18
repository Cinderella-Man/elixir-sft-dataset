  test "mixed scenario with matches, diffs, and uniques" do
    left = [
      %{id: 1, name: "Alice", status: "active"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 3, name: "Charlie", status: "inactive"}
    ]

    right = [
      # identical
      %{id: 1, name: "Alice", status: "active"},
      # status differs
      %{id: 2, name: "Bob", status: "inactive"},
      # only in right
      %{id: 4, name: "Diana", status: "active"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    # Totals
    assert length(result.matched) == 2
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1

    # Only-lists
    assert hd(result.only_in_left).id == 3
    assert hd(result.only_in_right).id == 4

    # Matched record with no diff
    alice = Enum.find(result.matched, &(&1.left.id == 1))
    assert alice.differences == %{}

    # Matched record with diff
    bob = Enum.find(result.matched, &(&1.left.id == 2))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}
  end