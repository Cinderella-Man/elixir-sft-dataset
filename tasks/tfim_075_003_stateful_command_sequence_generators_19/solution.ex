    property "account programs can be mapped to their final balance" do
      gen =
        StreamData.map(CommandGenerators.account_program(), fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal -> bal + a
            {:withdraw, a}, bal -> bal - a
          end)
        end)

      check all(balance <- gen) do
        assert is_integer(balance)
        assert balance >= 0
      end
    end