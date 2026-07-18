  test "key is cleared after flush, allowing a new batch", %{bc: bc} do
    assert {:ok, [:first]} =
             BatchCollector.submit(bc, :k, :first, fn items -> {:ok, items} end)

    assert {:ok, [:second]} =
             BatchCollector.submit(bc, :k, :second, fn items -> {:ok, items} end)
  end