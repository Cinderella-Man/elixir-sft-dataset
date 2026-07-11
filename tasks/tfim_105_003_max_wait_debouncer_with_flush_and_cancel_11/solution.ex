  test "call/4 returns :ok promptly even with a blocking func" do
    slow = fn -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> MaxWaitDebouncer.call("s", 50, 500, slow) end)
    assert micros < 100_000
  end