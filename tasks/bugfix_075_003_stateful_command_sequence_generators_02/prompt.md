# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

I need you to write a module for us called `CommandGenerators` — it's the piece I'm missing before I can do model-based property testing with `StreamData` and `ExUnitProperties`. What it needs to hand me is `StreamData` generators for *valid stateful command sequences*.

The whole reason this module exists is that it must never emit an invalid program. Every command in a sequence it generates has to satisfy its own precondition given the model state that all the earlier commands in that same sequence produced. So the generator threads a symbolic model along as it builds the list, and that means I can take any generated program, run it straight against the real system, and never filter or throw anything away.

There are two stateful generators I want in the public API, and they're independent of each other.

The first is `CommandGenerators.stack_program(max_length \\ 20)`, which gives me a list of `0..max_length` commands against a stack model. The commands are `{:push, integer}`, `:pop`, `:peek`, and `:clear`. The invariant I care about is that running the sequence against a stack must never `:pop` or `:peek` an empty stack — so `:pop`/`:peek` are only allowed to be generated when the modeled stack is non-empty, while `{:push, _}` and `:clear` are always fair game.

The second is `CommandGenerators.account_program(max_length \\ 20)`, which gives me a list of `0..max_length` commands against a bank-account model whose balance must never go negative. Commands here are `{:deposit, amount}` where amount is `1..1000`, and `{:withdraw, amount}` where amount is `1..current_balance`. A `:withdraw` can only be generated when the modeled balance is positive, and the amount it picks must not exceed the modeled balance at that point in the sequence.

One thing I want to be careful about: across many samples the full length range has to actually be reachable. The empty program (0 commands) must be an attainable output, and so must a program of exactly `max_length` commands — which incidentally means `max_length 0` yields only the empty program. Same goes for the endpoints of each amount and each command: given enough samples I should see deposits of both `1` and `1000`, withdrawals of both `1` and the entire current balance, and every single one of `:push`, `:pop`, `:peek`, `:clear`.

Both invariants have to be enforced *inside* the generators, by conditioning the set of available commands at each step on the current model state. I don't ever want a consumer of this to have to reach for `StreamData.filter/2`. And each generator needs to return a `%StreamData{}` struct so it composes with the standard `StreamData` combinators.

Send me the complete module in a single file, please. Only external dependency should be `stream_data`, nothing else.

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
      if size >= 0 do
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
3 of 18 test(s) failed:

  * property CommandGenerators.stack_program always produces a valid stack program
      
      
      Failed with generated values (after 0 successful runs):
      
               * Clause:    cmds <- CommandGenerators.stack_program()
                 Generated: [:peek, :clear, :pop, :clear, :pop, :clear, :peek, {:push, -145}, {:push, -196}, {:push, -441}, :clear, :clear, {:push, -979}, {:push, 0}]
      
           Expected truthy, got false
      code: assert stack_valid?(cmds)
      arguments:
      
               # 1
               [:peek, :clear, :pop, :clear, :pop, :clear, :peek, {:push, -145}, {:push, -196}, {:push, -441}, :clear, :clear, {:pus

  * property CommandGenerators.stack_program never pops or peeks an empty stack (prefix check)
      
      
      Failed with generated values (after 0 successful runs):
      
               * Clause:    cmds <- CommandGenerators.stack_program()
                 Generated: [:peek, :clear, :pop, :clear, :pop, :clear, :peek, {:push, -145}, {:push, -196}, {:push, -441}, :clear, :clear, {:push, -979}, {:push, 0}]
      
           Expected truthy, got false
      code: assert stack_valid?(Enum.take(cmds, n))
      arguments:
      
               # 1
               [:peek]
      
      

  * property composability with StreamData programs can be filtered to a minimum length without breaking validity
      
      
      Failed with generated values (after 0 successful runs):
      
               * Clause:    cmds <- gen
                 Generated: [{:push, 691}, :clear, :peek, {:push, 0}]
      
           Expected truthy, got false
      code: assert stack_valid?(cmds)
      arguments:
      
               # 1
               [{:push, 691}, :clear, :peek, {:push, 0}]
```
