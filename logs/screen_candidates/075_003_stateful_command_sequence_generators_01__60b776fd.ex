defmodule CommandGenerators do
  @moduledoc """
  `StreamData` generators for *valid* stateful command sequences.

  These generators are intended for model-based property testing with
  `StreamData` and `ExUnitProperties`. The defining characteristic is that they
  never emit an invalid program: every command in a generated sequence satisfies
  its precondition with respect to the symbolic model state produced by all of
  the commands preceding it.

  This is achieved by threading a symbolic model *inside* the generator. At each
  step, the set of commands that may be generated is conditioned on the current
  model state, and the chosen command is then applied to the model to obtain the
  state used for the next step. As a consequence, consumers never need
  `StreamData.filter/2` and no generated sequence is ever discarded.

  Two independent stateful generators are provided:

    * `stack_program/1` — sequences of `{:push, integer}`, `:pop`, `:peek` and
      `:clear` commands where `:pop`/`:peek` are only ever emitted when the
      modeled stack is non-empty.

    * `account_program/1` — sequences of `{:deposit, amount}` and
      `{:withdraw, amount}` commands where the modeled balance never becomes
      negative.

  Both functions return a `%StreamData{}` struct, so they compose with all of
  the standard `StreamData` combinators (`StreamData.map/2`,
  `StreamData.bind/2`, `StreamData.list_of/2`, and friends) and shrink
  naturally: shrinking removes commands from the tail of the sequence and
  shrinks the integers embedded in commands, both of which preserve validity.

  ## Example

      use ExUnitProperties

      property "the stack model matches the real stack" do
        check all commands <- CommandGenerators.stack_program() do
          # No filtering needed: `commands` is always runnable.
          Enum.reduce(commands, Stack.new(), &Stack.run(&2, &1))
        end
      end

  """

  @typedoc "A command understood by the stack model."
  @type stack_command :: {:push, integer()} | :pop | :peek | :clear

  @typedoc "A command understood by the bank-account model."
  @type account_command :: {:deposit, pos_integer()} | {:withdraw, pos_integer()}

  @typedoc "The symbolic stack model: the number of elements currently on the stack."
  @type stack_model :: non_neg_integer()

  @typedoc "The symbolic account model: the current balance, always non-negative."
  @type account_model :: non_neg_integer()

  @default_max_length 20
  @max_deposit 1000

  @doc """
  Generates a list of `0..max_length` stack commands that is always runnable.

  Commands are `{:push, integer}`, `:pop`, `:peek` and `:clear`. The generator
  threads a symbolic model — the current stack depth — through the sequence, so
  that `:pop` and `:peek` are only ever produced when the modeled stack is
  non-empty. `{:push, _}` and `:clear` are legal in every state.

  Running any generated sequence against a real stack therefore never pops or
  peeks an empty stack.

  ## Examples

      iex> program = CommandGenerators.stack_program(10)
      iex> match?(%StreamData{}, program)
      true

  """
  @spec stack_program(non_neg_integer()) :: StreamData.t([stack_command()])
  def stack_program(max_length \\ @default_max_length)
      when is_integer(max_length) and max_length >= 0 do
    program(max_length, 0, &stack_command/1, &apply_stack_command/2)
  end

  @doc """
  Generates a list of `0..max_length` bank-account commands that is always runnable.

  Commands are `{:deposit, amount}` with `amount` in `1..1000` and
  `{:withdraw, amount}` with `amount` in `1..balance`, where `balance` is the
  modeled balance at that point in the sequence. A `:withdraw` is only ever
  produced when the modeled balance is positive, and never for more than the
  modeled balance.

  Running any generated sequence against a real account therefore never drives
  the balance negative.

  ## Examples

      iex> program = CommandGenerators.account_program(10)
      iex> match?(%StreamData{}, program)
      true

  """
  @spec account_program(non_neg_integer()) :: StreamData.t([account_command()])
  def account_program(max_length \\ @default_max_length)
      when is_integer(max_length) and max_length >= 0 do
    program(max_length, 0, &account_command/1, &apply_account_command/2)
  end

  ## Generic stateful program generator

  # Picks a length in `0..max_length`, then builds a sequence of exactly that
  # many commands, threading `state` through `next_command` (which conditions the
  # available commands on the state) and `transition` (which advances the model).
  @spec program(
          non_neg_integer(),
          state,
          (state -> StreamData.t(command)),
          (state, command -> state)
        ) :: StreamData.t([command])
        when state: term(), command: term()
  defp program(max_length, initial_state, next_command, transition) do
    StreamData.bind(StreamData.integer(0..max_length), fn length ->
      commands(length, initial_state, next_command, transition, [])
    end)
  end

  @spec commands(
          non_neg_integer(),
          state,
          (state -> StreamData.t(command)),
          (state, command -> state),
          [command]
        ) :: StreamData.t([command])
        when state: term(), command: term()
  defp commands(0, _state, _next_command, _transition, acc) do
    StreamData.constant(Enum.reverse(acc))
  end

  defp commands(remaining, state, next_command, transition, acc) do
    StreamData.bind(next_command.(state), fn command ->
      commands(
        remaining - 1,
        transition.(state, command),
        next_command,
        transition,
        [command | acc]
      )
    end)
  end

  ## Stack model

  # Commands legal in the current stack state. `:pop`/`:peek` require a
  # non-empty stack; `{:push, _}` and `:clear` are always legal.
  @spec stack_command(stack_model()) :: StreamData.t(stack_command())
  defp stack_command(0) do
    StreamData.one_of([push_command(), StreamData.constant(:clear)])
  end

  defp stack_command(depth) when depth > 0 do
    StreamData.one_of([
      push_command(),
      StreamData.constant(:pop),
      StreamData.constant(:peek),
      StreamData.constant(:clear)
    ])
  end

  @spec push_command() :: StreamData.t({:push, integer()})
  defp push_command do
    StreamData.map(StreamData.integer(), &{:push, &1})
  end

  # Advances the symbolic stack model (the current depth).
  @spec apply_stack_command(stack_model(), stack_command()) :: stack_model()
  defp apply_stack_command(depth, {:push, _value}), do: depth + 1
  defp apply_stack_command(depth, :pop) when depth > 0, do: depth - 1
  defp apply_stack_command(depth, :peek), do: depth
  defp apply_stack_command(_depth, :clear), do: 0

  ## Bank-account model

  # Commands legal in the current account state. `:withdraw` requires a positive
  # balance and may never exceed it; `:deposit` is always legal.
  @spec account_command(account_model()) :: StreamData.t(account_command())
  defp account_command(0) do
    deposit_command()
  end

  defp account_command(balance) when balance > 0 do
    StreamData.one_of([deposit_command(), withdraw_command(balance)])
  end

  @spec deposit_command() :: StreamData.t({:deposit, pos_integer()})
  defp deposit_command do
    StreamData.map(StreamData.integer(1..@max_deposit), &{:deposit, &1})
  end

  @spec withdraw_command(pos_integer()) :: StreamData.t({:withdraw, pos_integer()})
  defp withdraw_command(balance) when balance > 0 do
    StreamData.map(StreamData.integer(1..balance), &{:withdraw, &1})
  end

  # Advances the symbolic account model (the current balance).
  @spec apply_account_command(account_model(), account_command()) :: account_model()
  defp apply_account_command(balance, {:deposit, amount}), do: balance + amount

  defp apply_account_command(balance, {:withdraw, amount}) when amount <= balance do
    balance - amount
  end
end