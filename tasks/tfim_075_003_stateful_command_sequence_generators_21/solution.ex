  test "push and clear are both offered on an empty modeled stack" do
    Process.put(:empty_stack_push, false)
    Process.put(:empty_stack_clear, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.stack_program(),
        [initial_seed: {31, 32, 33}, max_runs: 600],
        fn cmds ->
          Enum.reduce(cmds, 0, fn cmd, size ->
            case cmd do
              {:push, _} ->
                if size == 0, do: Process.put(:empty_stack_push, true)
                size + 1

              :clear ->
                if size == 0, do: Process.put(:empty_stack_clear, true)
                0

              :pop ->
                size - 1

              :peek ->
                size
            end
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:empty_stack_push),
           "no {:push, _} was ever generated on an empty modeled stack across 600 samples"

    assert Process.get(:empty_stack_clear),
           "no :clear was ever generated on an empty modeled stack across 600 samples"
  end