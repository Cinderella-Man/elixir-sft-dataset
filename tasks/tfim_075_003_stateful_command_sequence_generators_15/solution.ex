    property "deposit amounts are within 1..1000 and withdrawals are positive" do
      check all(cmds <- CommandGenerators.account_program()) do
        for cmd <- cmds do
          case cmd do
            {:deposit, a} ->
              assert a >= 1 and a <= 1000

            {:withdraw, a} ->
              assert a >= 1

            other ->
              flunk("unexpected command: #{inspect(other)}")
          end
        end
      end
    end