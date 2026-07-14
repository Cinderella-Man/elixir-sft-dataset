# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Saga do
  @moduledoc """
  Implements the Saga pattern for coordinating distributed transactions
  with automatic compensation on failure.

  ## Overview

  A saga is a sequence of named steps. Each step pairs a fallible
  *action* with an infallible *compensating action*. When any action
  fails, every action that already succeeded is compensated in reverse
  order, ensuring the system can be returned to a consistent state.

  ## Context threading

  Every action and compensating function receives the *accumulated*
  context map — the initial context merged with all results produced
  by steps that have run so far. A successful action's result is
  stored under the step's name:

      %{initial_key: value, reserve: reserve_result, charge: charge_result}

  Compensating functions receive the full context at the exact moment
  execution failed, so they have access to all data produced up to
  that point.

  ## Example

      saga =
        Saga.new()
        |> Saga.step(:reserve, &reserve_inventory/1, &release_inventory/1)
        |> Saga.step(:charge,  &charge_payment/1,   &refund_payment/1)
        |> Saga.step(:ship,    &create_shipment/1,   &cancel_shipment/1)

      case Saga.execute(saga, %{order_id: 42}) do
        {:ok, ctx} ->
          IO.inspect(ctx.ship, label: "shipment")

        {:error, failed_step, reason, compensations} ->
          IO.puts("Failed at \#{failed_step}: \#{inspect(reason)}")
          IO.inspect(compensations, label: "compensation results")
      end
  """

  @typedoc "A step stored inside the saga."
  @type step :: %{
          name: atom(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensate: (context() -> term())
        }

  @typedoc "The context map threaded through every action and compensation."
  @type context :: map()

  @typedoc "Keyword list of `[step_name: compensation_return_value]`."
  @type compensation_results :: keyword()

  @typedoc """
  Returned by `execute/2`.

    * `{:ok, final_context}` — every step succeeded.
    * `{:error, failed_step, reason, compensation_results}` — a step failed;
      all previously completed steps were compensated in reverse order.
  """
  @type execute_result ::
          {:ok, context()}
          | {:error, atom(), term(), compensation_results()}

  defstruct steps: []

  @type t :: %__MODULE__{steps: [step()]}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new, empty saga.

      iex> Saga.new()
      %Saga{steps: []}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Appends a named step to the saga.

  ## Parameters

    * `saga`          – the saga to extend.
    * `name`          – an atom that uniquely identifies the step. The
                        step's result will be stored in the context under
                        this key.
    * `action_fn`     – `(context -> {:ok, result} | {:error, reason})`.
                        Receives the current accumulated context.
    * `compensate_fn` – `(context -> any)`. Receives the context at the
                        point of failure. Its return value is recorded but
                        never causes a failure; any exception is caught and
                        recorded instead.

  Steps are executed in the order they are added.
  """
  @spec step(
          t(),
          atom(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term())
        ) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc """
  Executes the saga against an initial `context` map.

  Steps run strictly in the order they were added. Each successful
  step merges its result into the context under the step's name before
  the next step begins.

  On failure the compensating functions for all *completed* steps run
  in **reverse order**. Failures (or exceptions) inside a compensating
  function are caught, recorded, and never abort the remaining
  compensations.

  ## Return values

    * `{:ok, final_context}` — all steps succeeded.
    * `{:error, failed_step_name, reason, compensation_results}` — the
      step named `failed_step_name` returned `{:error, reason}`. The
      `compensation_results` keyword list contains one entry per
      compensated step, in reverse execution order.
  """
  @spec execute(t(), context()) :: execute_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run_steps(steps, [], context)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # No more steps — full success.
  @spec run_steps([step()], [step()], context()) :: execute_result()
  defp run_steps([], _completed, context), do: {:ok, context}

  defp run_steps(
         [%{name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe_action(action, context) do
      {:ok, result} ->
        enriched = Map.put(context, name, result)
        run_steps(rest, [step | completed], enriched)

      {:error, reason} ->
        # `completed` is already in reverse-execution order (most recent first)
        compensation_results = compensate_all(completed, context)
        {:error, name, reason, compensation_results}
    end
  end

  # Runs the action and normalises any unexpected return into an error.
  @spec safe_action((context() -> term()), context()) :: {:ok, term()} | {:error, term()}
  defp safe_action(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # Runs all compensations in order (which is already reverse-execution order)
  # and collects their results. Exceptions are caught and stored.
  @spec compensate_all([step()], context()) :: compensation_results()
  defp compensate_all(completed_steps, context) do
    Enum.map(completed_steps, fn %{name: name, compensate: compensate} ->
      result =
        try do
          compensate.(context)
        rescue
          exception -> {:exception, exception, __STACKTRACE__}
        catch
          kind, value -> {:caught, kind, value}
        end

      {name, result}
    end)
  end
end
```

## New specification

Write me an Elixir module called `Saga` that implements the Saga pattern **with a durable journal and crash-resumable execution**. Every run emits an ordered event journal, and a partially-completed run can be resumed from that journal without re-running steps that already finished.

Public API:
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a named step. `action_fn` receives the accumulated context and returns `{:ok, result}` or `{:error, reason}`; on success the result is merged under `name`. `compensate_fn` receives the context; its return value is recorded but never fails the chain.
- `Saga.execute(saga, context)` — runs all steps from the beginning.
- `Saga.resume(saga, context, journal)` — resumes from a previously produced journal.

Journal format — a list of events in **chronological** order:
- `{:completed, name, result}` — a step finished successfully with `result`.
- `{:failed, name, reason}` — a step returned `{:error, reason}`.
- `{:compensated, name, value}` — a completed step's compensation ran, returning `value`.

Return values (note the extra journal element):
- `{:ok, final_context, journal}` on full success.
- `{:error, failed_step_name, reason, compensation_results, journal}` on failure, where `compensation_results` is a keyword list `[step_name: value]` in reverse call order and `journal` is the complete chronological event list.

Resume semantics:
- `resume/3` reconstructs the context by merging every `{:completed, name, result}` from the incoming journal (under `name`), **without** re-invoking those actions. Assume completed steps form a prefix of the step list.
- It then runs the remaining steps, appending new events to (a copy of) the incoming journal's completed events so the returned journal stays chronological.
- If a later step fails during resume, **all** completed steps — those replayed from the journal *and* those newly run — are compensated in reverse order, using each step's compensating function from the saga definition.
- An empty journal makes `resume/3` behave exactly like `execute/2`.

Other behaviours: steps run strictly in order; each action/compensation sees the accumulated context; a raising compensating function must not abort the remaining compensations (catch and record it). Plain module with a struct — no GenServer, no processes, no external dependencies. Give me the complete implementation in a single file.

## Additional interface contract

- When a compensating function raises, the value recorded for that step (in `compensation_results` and in its `{:compensated, name, value}` journal event) is `{:exception, exception, stacktrace}` — a 3-tuple carrying the raised exception struct and the stacktrace it was caught with.
