  test "pop/peek stay available at the non-empty boundary, including states reached via pops" do
    # The precondition is exactly non-emptiness: :pop/:peek must be offered on a
    # one-element modeled stack, also when that state was reached after earlier
    # pops (i.e. the threaded model tracks the real stack, not an approximation).
    Process.put(:stack_boundary_hit, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.stack_program(),
        [initial_seed: {11, 22, 33}, max_runs: 600],
        fn cmds ->
          Enum.reduce(cmds, {0, 0}, fn cmd, {size, pops} ->
            case cmd do
              {:push, _} ->
                {size + 1, pops}

              :clear ->
                {0, 0}

              op when op in [:pop, :peek] ->
                if size == 1 and pops >= 1, do: Process.put(:stack_boundary_hit, true)
                if op == :pop, do: {size - 1, pops + 1}, else: {size, pops}
            end
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:stack_boundary_hit),
           "no :pop/:peek was ever generated on a one-element modeled stack reached " <>
             "after an earlier :pop (since the last :clear) across 600 seeded samples"
  end