  test "call/4 returns :ok promptly even when the handler would block" do
    slow = fn _batch -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> BatchDebouncer.call("s", 50, :item, slow) end)
    assert micros < 100_000
  end