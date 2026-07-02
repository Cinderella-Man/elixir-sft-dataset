  test "single item flushes after timer", %{bc: bc} do
    result =
      BatchCollector.submit(bc, :k, :item1, fn items ->
        {:ok, items}
      end)

    assert result == {:ok, [:item1]}
  end