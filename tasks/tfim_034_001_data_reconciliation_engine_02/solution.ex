  test "records present in both lists appear in :matched" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end