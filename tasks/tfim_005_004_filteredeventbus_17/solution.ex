  test "test_filter returns booleans without a running bus" do
    assert true = FilteredEventBus.test_filter([{:eq, [:a], 1}], %{a: 1})
    assert false == FilteredEventBus.test_filter([{:eq, [:a], 1}], %{a: 2})

    assert true = FilteredEventBus.test_filter([], %{anything: true})

    # Same validation as subscribe
    assert {:error, :invalid_filter} =
             FilteredEventBus.test_filter([{:bogus, [:a], 1}], %{a: 1})
  end