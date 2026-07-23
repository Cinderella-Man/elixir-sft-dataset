# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir module called `Saga` that implements the Saga pattern **with a pivot boundary and forward recovery**. Unlike a plain saga where every failure rolls everything back, this coordinator distinguishes two kinds of steps:

- **Compensable steps** — added with `Saga.step(saga, name, action_fn, compensate_fn)`. These come *before* the commit point and can be rolled back.
- **Retriable steps** — added with `Saga.retriable(saga, name, action_fn, max_attempts)`. These come *after* the commit point. They have no compensating action; instead, if the action fails it is retried (re-invoked with the same context) up to `max_attempts` total attempts. Retriable steps model post-commit work that must be driven *forward* to completion, not undone.

Public API:
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a compensable step. `action_fn` is a 1-arity function receiving the context map and returning `{:ok, result}` or `{:error, reason}`. `compensate_fn` is a 1-arity function receiving the context; its return value is recorded but never fails the compensation chain.
- `Saga.retriable(saga, name, action_fn, max_attempts)` — appends a retriable step. `max_attempts` is a positive integer; reject a non-positive value with a guard clause, so passing `0` or a negative number raises `FunctionClauseError`.
- `Saga.execute(saga, context)` — runs all steps in order, threading the context map (a successful step's result is merged under its name). On success, returns `{:ok, final_context}` — the accumulated context map (the original context for an empty saga).

Failure semantics:
- If a **compensable** step returns `{:error, reason}`, forward execution stops and the compensating actions of all previously completed **compensable** steps run in **reverse order**. Return `{:error, failed_step_name, reason, compensation_results}`, where `compensation_results` is a keyword list of `[step_name: compensate_return_value]` in reverse call order. Retriable steps are never compensated (they are post-commit).
- A **retriable** step that returns `{:error, reason}` is retried, re-invoking its action with the same context, until it returns `{:ok, result}` or `max_attempts` attempts have been made. On exhaustion, return `{:error, failed_step_name, {:retries_exhausted, last_reason}, []}` — note the empty compensation list, because committed compensable steps are **not** rolled back once the pivot has been crossed. `last_reason` is the reason from the final attempt.

Other behaviours to preserve:
- Steps run strictly in the order added; each action/compensation sees the accumulated context.
- A raising compensating function must not abort the remaining compensations; catch and record it (its recorded value may be any term).
- Plain module with a struct — no GenServer, no processes, no external dependencies.

Give me the complete implementation in a single file.

## The buggy module

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with a **pivot boundary** and **forward recovery**.

  Steps come in two kinds:

    * `:compensable` — added with `step/4`. These precede the commit point
      and can be rolled back by their compensating action.
    * `:retriable` — added with `retriable/4`. These follow the commit point.
      They have no compensation; on failure their action is retried up to
      `max_attempts`, driving the saga *forward* to completion.

  A failing compensable step rolls back previously completed compensable
  steps in reverse order. A retriable step that exhausts its attempts fails
  the saga *without* rolling anything back — the pivot has been crossed and
  committed work is not undone.
  """

  @typedoc "A step action: given the context, returns `{:ok, result}` or `{:error, reason}`."
  @type action :: (map() -> {:ok, term()} | {:error, term()})

  @typedoc "A compensating action: receives the context; its return value is recorded."
  @type compensate :: (map() -> term())

  @typedoc "A saga coordinator."
  @type t :: %__MODULE__{steps: [map()]}

  defstruct steps: []

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a compensable step (rolled back on an earlier-or-current failure)."
  @spec step(t(), atom(), action(), compensate()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :compensable, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Appends a retriable step (retried up to `max_attempts`, never compensated)."
  @spec retriable(t(), atom(), action(), pos_integer()) :: t()
  def retriable(%__MODULE__{} = saga, name, action_fn, max_attempts)
      when is_atom(name) and is_function(action_fn, 2) and is_integer(max_attempts) and
             max_attempts >= 1 do
    entry = %{kind: :retriable, name: name, action: action_fn, max_attempts: max_attempts}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga against an initial context map."
  @spec execute(t(), map()) :: {:ok, map()} | {:error, atom(), term(), keyword()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end

  # --- execution -----------------------------------------------------------

  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :compensable, name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe(action, context) do
      {:ok, result} ->
        run(rest, [step | completed], Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, reason, compensate_all(completed, context)}
    end
  end

  defp run(
         [%{kind: :retriable, name: name, action: action, max_attempts: max} | rest],
         completed,
         context
       ) do
    case attempt(action, context, max, 1) do
      {:ok, result} ->
        run(rest, completed, Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, {:retries_exhausted, reason}, []}
    end
  end

  defp attempt(action, context, max, n) do
    case safe(action, context) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        if n >= max, do: {:error, reason}, else: attempt(action, context, max, n + 1)
    end
  end

  defp safe(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # --- compensation --------------------------------------------------------

  defp compensate_all(completed, context) do
    Enum.map(completed, fn %{name: name, compensate: compensate} ->
      {name, safe_compensate(compensate, context)}
    end)
  end

  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```

## Failing test report

```
5 of 10 test(s) failed:

  * test retriable step retries until it succeeds and merges its result
      no function clause matching in Saga.retriable/4

  * test retriable step exhaustion returns error and compensates nothing
      no function clause matching in Saga.retriable/4

  * test retriable action is invoked exactly max_attempts times on exhaustion
      no function clause matching in Saga.retriable/4

  * test compensable failure after a retriable step never compensates the retriable step
      no function clause matching in Saga.retriable/4

  (…1 more)
```
