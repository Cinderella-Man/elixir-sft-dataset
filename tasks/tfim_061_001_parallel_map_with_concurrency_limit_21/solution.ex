  test "pmap preserves a trapping caller's own unrelated :EXIT mail" do
    was_trapping? = Process.flag(:trap_exit, true)

    try do
      victim = spawn_link(fn -> exit(:boom) end)

      # Wait until OUR trapped exit is genuinely queued — pmap must not eat it.
      wait = fn wait ->
        {:messages, msgs} = Process.info(self(), :messages)

        unless Enum.any?(msgs, &match?({:EXIT, ^victim, :boom}, &1)) do
          Process.sleep(5)
          wait.(wait)
        end
      end

      wait.(wait)

      # A crashing element forces pmap's own trapped task exits into the
      # mailbox alongside ours; its flush may only remove its own.
      results =
        ParallelMap.pmap(
          [1, :crash, 3],
          fn
            :crash -> raise "kaboom"
            x -> x * 2
          end,
          2
        )

      assert length(results) == 3

      assert_receive {:EXIT, ^victim, :boom}
      refute_receive {:EXIT, _, _}, 50
    after
      Process.flag(:trap_exit, was_trapping?)
    end
  end