    property "respects the length bound" do
      check all(cmds <- CommandGenerators.stack_program(10)) do
        assert length(cmds) <= 10
      end
    end