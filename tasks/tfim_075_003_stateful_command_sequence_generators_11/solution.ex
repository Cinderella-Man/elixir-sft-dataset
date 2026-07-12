    property "never pops or peeks an empty stack (prefix check)" do
      check all(cmds <- CommandGenerators.stack_program()) do
        # Every prefix must also be valid, which follows from validity of the
        # whole sequence, but we assert it explicitly for good measure.
        for n <- 0..length(cmds) do
          assert stack_valid?(Enum.take(cmds, n))
        end
      end
    end