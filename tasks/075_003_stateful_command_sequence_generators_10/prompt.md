# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `stack_program` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CommandGenerators` that provides `StreamData` generators for **valid stateful command sequences**, intended for model-based property testing with `StreamData` and `ExUnitProperties`.

The point of these generators is that they never emit an invalid program: each command in a generated sequence must satisfy its **precondition** given the model state produced by all the commands before it. The generator threads a symbolic model as it builds the sequence, so a consumer can run every generated program against a real system without ever having to filter or discard sequences.

I need two independent stateful generators in the public API:

- `CommandGenerators.stack_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a stack model. Commands are `{:push, integer}`, `:pop`, `:peek`, and `:clear`. The invariant: running the sequence against a stack must never `:pop` or `:peek` an empty stack. So `:pop`/`:peek` may only be generated when the modeled stack is non-empty; `{:push, _}` and `:clear` are always allowed.

- `CommandGenerators.account_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a bank-account model whose balance must never go negative. Commands are `{:deposit, amount}` (amount `1..1000`) and `{:withdraw, amount}` (amount `1..current_balance`). A `:withdraw` may only be generated when the modeled balance is positive, and its amount must not exceed the modeled balance at that point.

Across many samples the full length range must be reachable: both the empty program (0 commands) and a program of exactly `max_length` commands must be attainable outputs (so `max_length 0` yields only the empty program). Likewise the range endpoints of each amount and command must be reachable — deposits of both `1` and `1000`, withdrawals of both `1` and the entire current balance, and every one of `:push`, `:pop`, `:peek`, `:clear` must all be generated given enough samples.

Both invariants must be enforced *inside* the generators by conditioning each step's available commands on the current model state — consumers must never need `StreamData.filter/2`. Each generator must return a `%StreamData{}` struct that composes with the standard `StreamData` combinators.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.

## The module with `stack_program` missing

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

  def stack_program(max_length \\ 20) when is_integer(max_length) and max_length >= 0 do
    # TODO
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

Give me only the complete implementation of `stack_program` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
