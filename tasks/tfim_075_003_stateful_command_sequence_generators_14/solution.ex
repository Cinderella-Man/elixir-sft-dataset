    property "respects the length bound" do
      check all(cmds <- CommandGenerators.account_program(12)) do
        assert length(cmds) <= 12
      end
    end