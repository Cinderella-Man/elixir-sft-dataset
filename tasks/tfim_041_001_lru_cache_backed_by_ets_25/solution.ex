  test "the two backing tables are named, typed and protected as documented" do
    c = start_cache(2)

    data = data_table(c)
    order = order_table(c)

    # Both tables exist under the deterministic names derived from :name.
    assert :ets.info(data, :named_table) == true
    assert :ets.info(order, :named_table) == true

    # The data table: a :set for O(1) lookups, readable from any process, and
    # optimised for the direct concurrent reads the read path performs.
    assert :ets.info(data, :type) == :set
    assert :ets.info(data, :protection) == :public
    assert :ets.info(data, :read_concurrency) == true

    # The order table: an :ordered_set so the LRU entry is found in O(log n);
    # only the owning GenServer writes to it.
    assert :ets.info(order, :type) == :ordered_set
    assert :ets.info(order, :protection) == :protected
  end