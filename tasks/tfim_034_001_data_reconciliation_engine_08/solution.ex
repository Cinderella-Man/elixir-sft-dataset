  test "both lists empty" do
    result = Reconciler.reconcile([], [], key_fields: [:id])
    assert result == %{matched: [], only_in_left: [], only_in_right: []}
  end