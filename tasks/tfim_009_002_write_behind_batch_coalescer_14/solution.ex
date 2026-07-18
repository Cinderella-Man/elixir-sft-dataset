  test "pending_count returns 0 for unknown key", %{bc: bc} do
    assert BatchCollector.pending_count(bc, :nothing) == 0
  end