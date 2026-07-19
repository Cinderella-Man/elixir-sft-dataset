# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`stack_program/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `stack_program/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `stack_program/1` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
