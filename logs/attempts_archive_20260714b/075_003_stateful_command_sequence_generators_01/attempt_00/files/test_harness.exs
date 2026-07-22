defmodule CommandGeneratorsTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  # -------------------------------------------------------
  # Reference model executors (used only to *verify* generated programs)
  # -------------------------------------------------------

  defp stack_valid?(cmds) do
    Enum.reduce_while(cmds, 0, fn cmd, size ->
      case cmd do
        {:push, v} when is_integer(v) -> {:cont, size + 1}
        :pop -> if size > 0, do: {:cont, size - 1}, else: {:halt, :invalid}
        :peek -> if size > 0, do: {:cont, size}, else: {:halt, :invalid}
        :clear -> {:cont, 0}
        _ -> {:halt, :invalid}
      end
    end) != :invalid
  end

  defp account_valid?(cmds) do
    Enum.reduce_while(cmds, 0, fn cmd, bal ->
      case cmd do
        {:deposit, a} when is_integer(a) and a >= 1 and a <= 1000 ->
          {:cont, bal + a}

        {:withdraw, a} when is_integer(a) and a >= 1 and a <= bal ->
          {:cont, bal - a}

        _ ->
          {:halt, :invalid}
      end
    end) != :invalid
  end

  # -------------------------------------------------------
  # CommandGenerators.stack_program/0,1
  # -------------------------------------------------------

  describe "CommandGenerators.stack_program" do
    property "always produces a valid stack program" do
      check all(cmds <- CommandGenerators.stack_program()) do
        assert is_list(cmds)
        assert stack_valid?(cmds)
      end
    end

    property "respects the length bound" do
      check all(cmds <- CommandGenerators.stack_program(10)) do
        assert length(cmds) <= 10
      end
    end

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

    property "never pops or peeks an empty stack (prefix check)" do
      check all(cmds <- CommandGenerators.stack_program()) do
        # Every prefix must also be valid, which follows from validity of the
        # whole sequence, but we assert it explicitly for good measure.
        for n <- 0..length(cmds) do
          assert stack_valid?(Enum.take(cmds, n))
        end
      end
    end

    property "produces both pushes and pops across many samples" do
      commands =
        Enum.flat_map(1..300, fn _ ->
          [cmds] = Enum.take(CommandGenerators.stack_program(), 1)
          cmds
        end)

      assert Enum.any?(commands, &match?({:push, _}, &1))
      assert :pop in commands
    end
  end

  # -------------------------------------------------------
  # CommandGenerators.account_program/0,1
  # -------------------------------------------------------

  describe "CommandGenerators.account_program" do
    property "always produces a valid account program (balance never negative)" do
      check all(cmds <- CommandGenerators.account_program()) do
        assert is_list(cmds)
        assert account_valid?(cmds)
      end
    end

    property "respects the length bound" do
      check all(cmds <- CommandGenerators.account_program(12)) do
        assert length(cmds) <= 12
      end
    end

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

    property "no withdrawal ever exceeds the modeled balance at that point" do
      check all(cmds <- CommandGenerators.account_program()) do
        Enum.reduce(cmds, 0, fn
          {:deposit, a}, bal ->
            bal + a

          {:withdraw, a}, bal ->
            assert a <= bal
            bal - a
        end)
      end
    end

    property "produces both deposits and withdrawals across many samples" do
      commands =
        Enum.flat_map(1..300, fn _ ->
          [cmds] = Enum.take(CommandGenerators.account_program(), 1)
          cmds
        end)

      assert Enum.any?(commands, &match?({:deposit, _}, &1))
      assert Enum.any?(commands, &match?({:withdraw, _}, &1))
    end
  end

  # -------------------------------------------------------
  # Composability
  # -------------------------------------------------------

  describe "composability with StreamData" do
    property "programs can be filtered to a minimum length without breaking validity" do
      gen = StreamData.filter(CommandGenerators.stack_program(), &(length(&1) >= 1))

      check all(cmds <- gen) do
        assert length(cmds) >= 1
        assert stack_valid?(cmds)
      end
    end

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
  end
end