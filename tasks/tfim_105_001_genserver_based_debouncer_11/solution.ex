  test "call/3 returns promptly even when the eventual func would block" do
    slow = fn ->
      Process.sleep(300)
      send(self(), :never_matters)
    end

    # Scheduling must not block on the func's future runtime.
    {micros, :ok} = :timer.tc(fn -> Debouncer.call("slow", 50, slow) end)
    assert micros < 100_000
  end