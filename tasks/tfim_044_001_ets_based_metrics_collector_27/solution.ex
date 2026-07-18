  test "gauge and reset still work while the owning GenServer is suspended" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.gauge(:hot_gauge, 12)
      assert Metrics.get(:hot_gauge) == 12
      assert :ok = Metrics.reset(:hot_gauge)
      assert Metrics.get(:hot_gauge) == 0
    after
      :sys.resume(Metrics)
    end
  end