  test "take_matches on a fresh server is empty" do
    pid = start!(key_fields: [:id])
    assert StreamReconciler.take_matches(pid) == []
  end