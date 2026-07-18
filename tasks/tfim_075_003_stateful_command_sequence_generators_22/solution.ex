  test "the stack command set is fully reachable: peek and clear are both generated" do
    Process.put(:stack_cmd_kinds, MapSet.new())

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.stack_program(),
        [initial_seed: {41, 42, 43}, max_runs: 600],
        fn cmds ->
          kinds =
            Enum.reduce(cmds, Process.get(:stack_cmd_kinds), fn
              {:push, _}, acc -> MapSet.put(acc, :push)
              cmd, acc -> MapSet.put(acc, cmd)
            end)

          Process.put(:stack_cmd_kinds, kinds)
          {:ok, cmds}
        end
      )

    kinds = Process.get(:stack_cmd_kinds)

    for kind <- [:push, :pop, :peek, :clear] do
      assert kind in kinds, "the documented command #{inspect(kind)} was never generated"
    end
  end