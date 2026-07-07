  test "remove of unknown id returns not_found", %{server: s} do
    assert {:error, :not_found} = IntervalRegistry.remove(s, 9999)
    {:ok, id} = IntervalRegistry.insert(s, {1, 2})
    assert :ok = IntervalRegistry.remove(s, id)
    # removing again fails
    assert {:error, :not_found} = IntervalRegistry.remove(s, id)
  end