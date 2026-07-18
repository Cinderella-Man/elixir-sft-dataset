  test "empty map returns empty map", %{m: m} do
    assert LogMasker.mask(m, %{}) == %{}
  end