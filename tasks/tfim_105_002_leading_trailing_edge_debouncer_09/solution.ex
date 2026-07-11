  test "call/4 returns :ok and does not block on the func" do
    slow = fn ->
      Process.sleep(300)
      :ok
    end

    {micros, :ok} = :timer.tc(fn -> EdgeDebouncer.call("s", 50, slow) end)
    assert micros < 100_000
  end