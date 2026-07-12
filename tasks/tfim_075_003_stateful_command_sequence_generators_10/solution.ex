    property "every command is drawn from the allowed command set" do
      check all(cmds <- CommandGenerators.stack_program()) do
        for cmd <- cmds do
          case cmd do
            {:push, v} -> assert is_integer(v)
            other -> assert other in [:pop, :peek, :clear]
          end
        end
      end
    end