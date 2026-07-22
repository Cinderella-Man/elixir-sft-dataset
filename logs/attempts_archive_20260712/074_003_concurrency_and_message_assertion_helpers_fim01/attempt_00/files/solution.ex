  @spec process_exits(pid(), non_neg_integer()) :: :ok
  def process_exits(pid, timeout_ms \\ 1_000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _object, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])

        ExUnit.Assertions.flunk("""
        assert_process_exits timed out

          process : #{inspect(pid)}
          alive?  : #{Process.alive?(pid)}
          waited  : #{timeout_ms}ms
          the process did not terminate within the timeout
        """)
    end
  end