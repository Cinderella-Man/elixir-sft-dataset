# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `step`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Saga / Compensating Transaction Coordinator

Write me an Elixir module called `Saga` that executes a **saga**: a sequence of
steps where each step has a forward **action** and a **compensating action**. If
any step fails, the coordinator undoes the work already done by running the
compensating actions for all previously-completed steps, in reverse order.

Use only the Elixir/OTP standard library — no external dependencies. Give me the
complete module in a single file.

## Public API

The module must support this fluent, pipe-friendly interface:

```elixir
Saga.new()
|> Saga.step(:reserve, &reserve/1, &cancel_reservation/1)
|> Saga.step(:charge,  &charge/1,  &refund/1)
|> Saga.step(:ship,    &ship/1,    &unship/1)
|> Saga.execute(%{order_id: 42})
```

### `Saga.new/0`

Returns a new, empty saga value (any internal representation you like — treat it
as opaque).

### `Saga.step(saga, name, action, compensation)`

Appends a step to the saga and returns the updated saga.

- `name` — an identifier for the step (typically an atom).
- `action` — a 1-arity function that receives the current **context** (a map).
  It must return either:
  - `{:ok, result}` — the step succeeded; or
  - `{:error, reason}` — the step failed.
- `compensation` — a 1-arity function that receives the current context and
  undoes the step's effect. Its return value is recorded (by convention return
  `{:ok, _}` / `{:error, _}`, but any term is allowed).

Steps run in the order they were added.

### `Saga.execute(saga, context)`

Runs the saga starting from the given `context` map.

**Forward pass.** For each step in order, call its `action` with the current
context:

- On `{:ok, result}`: store the result in the context under the step's `name`
  key (i.e. `Map.put(context, name, result)`), mark the step **completed**, and
  continue to the next step. Later steps therefore see the results of earlier
  steps in their context.
- On `{:error, reason}`: stop the forward pass immediately (do **not** run any
  further steps' actions) and begin the compensation pass.

**Compensation pass.** Run the `compensation` of every **completed** step in
**reverse** completion order (most recently completed first). Each compensation
receives the context as accumulated up to the point of failure (which includes
that step's own stored result). Compensation is **best-effort**: if a
compensation returns `{:error, _}`, record it but still run the remaining
compensations.

Note: the step that *failed* is not "completed", so its compensation is **not**
run.

### Return values

- **All steps succeed:** return `{:ok, final_context}`, where `final_context` is
  the starting context with every step's result merged in under its name key.
- **A step fails:** return `{:error, error}` where `error` is a map with exactly
  these keys:
  - `:step` — the `name` of the step whose action returned `{:error, _}`.
  - `:error` — the `reason` from that failing action.
  - `:compensated` — a list of the step names whose compensations were run, in
    the order they ran (i.e. reverse of completion order).
  - `:compensations` — a map of `name => compensation_return_value` for each
    compensation that was run.
- **Empty saga** (no steps): return `{:ok, context}` unchanged.

## Example

```elixir
saga =
  Saga.new()
  |> Saga.step(:a, fn _ctx -> {:ok, 10} end, fn _ctx -> {:ok, :undo_a} end)
  |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 5} end, fn _ctx -> {:ok, :undo_b} end)

Saga.execute(saga, %{})
#=> {:ok, %{a: 10, b: 15}}
```

If step `:b` had instead returned `{:error, :nope}`, the result would be:

```elixir
{:error, %{
  step: :b,
  error: :nope,
  compensated: [:a],
  compensations: %{a: {:ok, :undo_a}}
}}
```

## The module with `step` missing

```elixir
defmodule Saga do
  @moduledoc """
  A saga / compensating-transaction coordinator.

  A saga is a sequence of steps, each with a forward *action* and a
  *compensating action*. Steps are executed in the order they were added. If any
  step's action fails, the coordinator undoes the work already performed by
  running the compensating actions of all previously-completed steps, in reverse
  completion order.

  ## Example

      Saga.new()
      |> Saga.step(:reserve, &reserve/1, &cancel_reservation/1)
      |> Saga.step(:charge,  &charge/1,  &refund/1)
      |> Saga.step(:ship,    &ship/1,    &unship/1)
      |> Saga.execute(%{order_id: 42})

  """

  @typedoc "An opaque saga value."
  @opaque t :: %__MODULE__{steps: [step()]}

  @typedoc "The context passed between steps."
  @type context :: map()

  @typedoc "An individual step in the saga."
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term())
        }

  @typedoc "The error map returned when a step fails."
  @type error :: %{
          step: term(),
          error: term(),
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  defstruct steps: []

  @doc """
  Returns a new, empty saga.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step to the saga and returns the updated saga.

  Steps run in the order they were added.

    * `name` — an identifier for the step (typically an atom).
    * `action` — a 1-arity function receiving the current context; must return
      `{:ok, result}` or `{:error, reason}`.
    * `compensation` — a 1-arity function receiving the current context that
      undoes the step's effect. Its return value is recorded.
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term())
        ) ::
          t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation)
      when is_function(action, 1) and is_function(compensation, 1) do
    # TODO
  end

  @doc """
  Runs the saga starting from the given `context` map.

  Returns `{:ok, final_context}` if every step succeeds, or `{:error, error}`
  (see `t:error/0`) if a step's action fails, after best-effort compensation of
  the previously-completed steps.
  """
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # Forward pass: execute each remaining step's action in order.
  #
  # `completed` accumulates the completed steps in reverse completion order
  # (most-recently-completed first), which is exactly the order needed for the
  # compensation pass.
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([%{name: name, action: action} = step | rest], context, completed) do
    case action.(context) do
      {:ok, result} ->
        new_context = Map.put(context, name, result)
        forward(rest, new_context, [step | completed])

      {:error, reason} ->
        compensate(completed, context, name, reason)
    end
  end

  # Compensation pass: run each completed step's compensation in reverse
  # completion order (best-effort — errors are recorded but do not stop the pass).
  defp compensate(completed, context, failed_step, reason) do
    {compensated, compensations} =
      Enum.reduce(completed, {[], %{}}, fn %{name: name, compensation: compensation},
                                           {names, results} ->
        result = compensation.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       step: failed_step,
       error: reason,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```

Output only `step` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
