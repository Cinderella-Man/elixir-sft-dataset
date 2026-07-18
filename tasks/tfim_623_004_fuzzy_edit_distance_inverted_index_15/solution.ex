  test "removing a non-existent document does not raise", %{idx: idx} do
    assert :ok = FuzzyIndex.remove(idx, "nonexistent")
  end