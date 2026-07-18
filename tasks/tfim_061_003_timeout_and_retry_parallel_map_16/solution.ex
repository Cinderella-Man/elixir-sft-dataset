  test "ConcurrencyCounter honours the :name option and returns new values" do
    {:ok, _pid} = ConcurrencyCounter.start_link(name: :retry_map_named_counter)

    assert ConcurrencyCounter.increment(:retry_map_named_counter) == 1
    assert ConcurrencyCounter.increment(:retry_map_named_counter) == 2
    assert ConcurrencyCounter.decrement(:retry_map_named_counter) == 1
    assert ConcurrencyCounter.peak(:retry_map_named_counter) == 2
  end