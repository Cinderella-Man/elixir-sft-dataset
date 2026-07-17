# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CommandGenerators do
  @moduledoc """
  `StreamData` generators for **valid stateful command sequences**, for use with
  model-based property testing via `StreamData` and `ExUnitProperties`.

  Each generator threads a *symbolic model* while it builds a sequence: at every
  step the set of commands offered is conditioned on the current model state, so
  a command's precondition is satisfied by construction. The result is that a
  consumer can run every generated program against a real system without ever
  filtering out invalid sequences.

  ## Usage

      use ExUnitProperties

      property "the stack never underflows" do
        check all program <- CommandGenerators.stack_program() do
          assert run_stack(program) != :underflow
        end
      end

  All generators return `%StreamData{}` structs and compose with the standard
  `StreamData` combinator API.
  """

  alias StreamData, as: SD

  # ---------------------------------------------------------------------------
  # Stack model
  # ---------------------------------------------------------------------------

  @doc """
  Produces a valid program of `0..max_length` stack commands.

  Commands: `{:push, integer}`, `:pop`, `:peek`, `:clear`. `:pop`/`:peek` are
  only offered when the modeled stack is non-empty, so running the program can
  never underflow.
  """
  @spec stack_program(non_neg_integer()) :: StreamData.t([term()])
  def stack_program(max_length \\ 20) when is_integer(max_length) and max_length >= 0 do
    SD.bind(SD.integer(0..max_length), fn n ->
      stack_build(n, 0, [])
    end)
  end

  # `size` is the only piece of stack state the preconditions depend on.
  defp stack_build(0, _size, acc), do: SD.constant(Enum.reverse(acc))

  defp stack_build(n, size, acc) do
    SD.bind(stack_command(size), fn cmd ->
      stack_build(n - 1, stack_apply(size, cmd), [cmd | acc])
    end)
  end

  defp stack_command(size) do
    push = SD.map(SD.integer(-1000..1000), fn v -> {:push, v} end)
    base = [push, SD.constant(:clear)]

    choices =
      if size > 0 do
        base ++ [SD.constant(:pop), SD.constant(:peek)]
      else
        base
      end

    SD.one_of(choices)
  end

  defp stack_apply(size, {:push, _v}), do: size + 1
  defp stack_apply(size, :pop), do: size - 1
  defp stack_apply(size, :peek), do: size
  defp stack_apply(_size, :clear), do: 0

  # ---------------------------------------------------------------------------
  # Bank-account model
  # ---------------------------------------------------------------------------

  @doc """
  Produces a valid program of `0..max_length` account commands.

  Commands: `{:deposit, 1..1000}` and `{:withdraw, 1..balance}`. `:withdraw` is
  only offered when the modeled balance is positive, and its amount is bounded by
  the current balance, so the balance can never go negative.
  """
  @spec account_program(non_neg_integer()) :: StreamData.t([term()])
  def account_program(max_length \\ 20) when is_integer(max_length) and max_length >= 0 do
    SD.bind(SD.integer(0..max_length), fn n ->
      account_build(n, 0, [])
    end)
  end

  defp account_build(0, _bal, acc), do: SD.constant(Enum.reverse(acc))

  defp account_build(n, bal, acc) do
    SD.bind(account_command(bal), fn cmd ->
      account_build(n - 1, account_apply(bal, cmd), [cmd | acc])
    end)
  end

  defp account_command(bal) do
    deposit = SD.map(SD.integer(1..1000), fn a -> {:deposit, a} end)

    if bal > 0 do
      withdraw = SD.map(SD.integer(1..bal), fn a -> {:withdraw, a} end)
      SD.one_of([deposit, withdraw])
    else
      deposit
    end
  end

  defp account_apply(bal, {:deposit, a}), do: bal + a
  defp account_apply(bal, {:withdraw, a}), do: bal - a
end
```

## Test harness — implement the `# TODO` test

```elixir
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

  # -------------------------------------------------------
  # Documented bounds and endpoints, via deterministic seeded sampling
  # (StreamData.check_all/3 with a fixed :initial_seed)
  # -------------------------------------------------------

  test "stack_program/0 defaults to max_length 20: lengths in 0..20, both endpoints occur" do
    Process.put(:stack_lengths, [])

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.stack_program(),
        [initial_seed: {11, 22, 33}, max_runs: 600],
        fn cmds ->
          Process.put(:stack_lengths, [length(cmds) | Process.get(:stack_lengths)])
          {:ok, cmds}
        end
      )

    lengths = Process.get(:stack_lengths)
    assert Enum.all?(lengths, &(&1 in 0..20))
    assert 0 in lengths, "the empty program (0 commands) was never generated"
    assert 20 in lengths, "the documented default maximum of 20 commands was never attained"
  end

  test "account_program/0 defaults to max_length 20: lengths in 0..20, both endpoints occur" do
    Process.put(:account_lengths, [])

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {44, 55, 66}, max_runs: 600],
        fn cmds ->
          Process.put(:account_lengths, [length(cmds) | Process.get(:account_lengths)])
          {:ok, cmds}
        end
      )

    lengths = Process.get(:account_lengths)
    assert Enum.all?(lengths, &(&1 in 0..20))
    assert 0 in lengths, "the empty program (0 commands) was never generated"
    assert 20 in lengths, "the documented default maximum of 20 commands was never attained"
  end

  test "max_length 0 is a valid argument and produces only the empty program" do
    stack_gen = CommandGenerators.stack_program(0)
    account_gen = CommandGenerators.account_program(0)

    assert match?(%StreamData{}, stack_gen)
    assert match?(%StreamData{}, account_gen)

    for {gen, seed} <- [{stack_gen, {1, 2, 3}}, {account_gen, {4, 5, 6}}] do
      {:ok, _} =
        StreamData.check_all(gen, [initial_seed: seed, max_runs: 50], fn cmds ->
          if cmds == [], do: {:ok, cmds}, else: {:error, cmds}
        end)
    end
  end

  test "deposit amounts respect the documented 1..1000 range and attain both endpoints" do
    # TODO
  end

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

  test "withdraw stays available at the positive-balance boundary (balance exactly 1)" do
    # A positive balance is the documented precondition, so a withdrawal must be
    # possible when the modeled balance is exactly 1.
    Process.put(:withdraw_at_one, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {101, 102, 103}, max_runs: 4000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if bal == 1, do: Process.put(:withdraw_at_one, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_at_one),
           "no :withdraw was ever generated at a modeled balance of exactly 1 " <>
             "across 4000 seeded samples"
  end

  test "withdrawals attain the documented upper endpoint: the whole modeled balance" do
    Process.put(:withdraw_full_balance, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {201, 202, 203}, max_runs: 3000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if a == bal and bal > 1, do: Process.put(:withdraw_full_balance, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_full_balance),
           "no :withdraw ever drew the documented upper endpoint of its 1..current_balance " <>
             "range (amount == modeled balance > 1) across 3000 seeded samples"
  end

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

  test "withdrawals attain the documented lower endpoint 1 while the balance exceeds 1" do
    Process.put(:withdraw_amount_one, false)

    {:ok, _} =
      StreamData.check_all(
        CommandGenerators.account_program(),
        [initial_seed: {51, 52, 53}, max_runs: 3000],
        fn cmds ->
          Enum.reduce(cmds, 0, fn
            {:deposit, a}, bal ->
              bal + a

            {:withdraw, a}, bal ->
              if a == 1 and bal > 1, do: Process.put(:withdraw_amount_one, true)
              bal - a
          end)

          {:ok, cmds}
        end
      )

    assert Process.get(:withdraw_amount_one),
           "no :withdraw of the documented lower endpoint amount 1 was ever generated at a " <>
             "modeled balance greater than 1 across 3000 seeded samples"
  end
end
```
