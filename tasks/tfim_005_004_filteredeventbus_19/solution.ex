  test "dead subscriber is removed from all topics", %{bus: bus} do
    task =
      Task.async(fn ->
        {:ok, _} = FilteredEventBus.subscribe(bus, "a", self())
        {:ok, _} = FilteredEventBus.subscribe(bus, "b", self(), [{:eq, [:x], 1}])
        :ready
      end)

    assert :ready = Task.await(task)

    # The bus processes the :DOWN message asynchronously, so poll through the
    # documented publish/3 matched-count until both subscriptions are gone.
    # Internal state is deliberately not inspected; the observable contract is
    # that a dead subscriber no longer counts as a match on any of its topics.
    removed? =
      Enum.any?(1..50, fn _ ->
        if FilteredEventBus.publish(bus, "a", %{}) == {:ok, 0} and
             FilteredEventBus.publish(bus, "b", %{x: 1}) == {:ok, 0} do
          true
        else
          Process.sleep(10)
          false
        end
      end)

    assert removed?
    assert Process.alive?(bus)
  end