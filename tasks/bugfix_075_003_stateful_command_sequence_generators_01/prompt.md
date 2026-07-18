# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `CommandGenerators` that provides `StreamData` generators for **valid stateful command sequences**, intended for model-based property testing with `StreamData` and `ExUnitProperties`.

The point of these generators is that they never emit an invalid program: each command in a generated sequence must satisfy its **precondition** given the model state produced by all the commands before it. The generator threads a symbolic model as it builds the sequence, so a consumer can run every generated program against a real system without ever having to filter or discard sequences.

I need two independent stateful generators in the public API:

- `CommandGenerators.stack_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a stack model. Commands are `{:push, integer}`, `:pop`, `:peek`, and `:clear`. The invariant: running the sequence against a stack must never `:pop` or `:peek` an empty stack. So `:pop`/`:peek` may only be generated when the modeled stack is non-empty; `{:push, _}` and `:clear` are always allowed.

- `CommandGenerators.account_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a bank-account model whose balance must never go negative. Commands are `{:deposit, amount}` (amount `1..1000`) and `{:withdraw, amount}` (amount `1..current_balance`). A `:withdraw` may only be generated when the modeled balance is positive, and its amount must not exceed the modeled balance at that point.

Across many samples the full length range must be reachable: both the empty program (0 commands) and a program of exactly `max_length` commands must be attainable outputs (so `max_length 0` yields only the empty program). Likewise the range endpoints of each amount and command must be reachable — deposits of both `1` and `1000`, withdrawals of both `1` and the entire current balance, and every one of `:push`, `:pop`, `:peek`, `:clear` must all be generated given enough samples.

Both invariants must be enforced *inside* the generators by conditioning each step's available commands on the current model state — consumers must never need `StreamData.filter/2`. Each generator must return a `%StreamData{}` struct that composes with the standard `StreamData` combinators.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.

## The buggy module

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
  def stack_program(max_length \\ 21) when is_integer(max_length) and max_length >= 0 do
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

## Failing test report

```
1 of 18 test(s) failed:

  * test stack_program/0 defaults to max_length 20: lengths in 0..20, both endpoints occur
      
      
      Expected truthy, got false
      code: assert Enum.all?(lengths, &(&1 in 0..20))
      arguments:
      
               # 1
               [4, 13, 10, 11, 18, 21, 7, 19, 12, 11, 19, 12, 12, 1, 17, 15, 16, 12, 10, 15, 19, 9, 19, 18, 17, 17, 12, 5, 20, 5, 10, 8, 2, 15, 16, 8, 19, 21, 12, 9, 20, 20, 14, 1, 1, 14, 13, 21, 21, 6, 20, 20, 21, 4, 16, 13, 19, 5, 16, 9, 13, 0, 7, 21, 13, 16, 17, 10, 9, 5, 10, 14, 7, 15, 11, 14, 2, 0, 0, 8, 21, 21, 13, 8, 10, 12, 0, 4, 18, 15, 4, 14, 20, 12, 18, 13, 3, 13, 5, 3, 10, 12, 2, 10, 9, 9,
```
