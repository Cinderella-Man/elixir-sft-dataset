  test "increment and get still work while the owning GenServer is suspended" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.increment(:hot_path, 3)
      assert :ok = Metrics.increment(:hot_path)
      assert Metrics.get(:hot_path) == 4
    after
      :sys.resume(Metrics)
    end
  end