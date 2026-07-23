# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `new`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

I need you to write me an Elixir module called `Saga` — it implements the Saga pattern, but with a pivot boundary and forward recovery rather than the plain version where any failure unwinds everything. The whole point is that this coordinator treats two kinds of steps differently.

The first kind is compensable steps, which I add with `Saga.step(saga, name, action_fn, compensate_fn)`. Those live *before* the commit point, so they can be rolled back. The second kind is retriable steps, added via `Saga.retriable(saga, name, action_fn, max_attempts)`. Those live *after* the commit point. They have no compensating action at all — instead, when the action fails, we retry it (re-invoking it with the same context) up to `max_attempts` total attempts. Retriable steps are how I model post-commit work that has to be driven *forward* to completion instead of undone.

For the public surface: `Saga.new()` creates a new, empty saga struct. `Saga.step(saga, name, action_fn, compensate_fn)` appends a compensable step, where `action_fn` is a 1-arity function that receives the context map and returns either `{:ok, result}` or `{:error, reason}`, and `compensate_fn` is a 1-arity function receiving the context — its return value gets recorded, but it never fails the compensation chain. `Saga.retriable(saga, name, action_fn, max_attempts)` appends a retriable step; `max_attempts` has to be a positive integer, and I want a non-positive value rejected with a guard clause, so that passing `0` or a negative number raises `FunctionClauseError`. Finally, `Saga.execute(saga, context)` runs all the steps in order, threading the context map through (a successful step's result gets merged under its name), and on success returns `{:ok, final_context}` — the accumulated context map, which for an empty saga is just the original context.

Now the failure side, which is the part I care most about. If a compensable step returns `{:error, reason}`, forward execution stops and the compensating actions of all previously completed compensable steps run in reverse order. The return is `{:error, failed_step_name, reason, compensation_results}`, where `compensation_results` is a keyword list of `[step_name: compensate_return_value]` in reverse call order. Retriable steps are never compensated — they're post-commit.

A retriable step that returns `{:error, reason}` gets retried, re-invoking its action with the same context, until either it returns `{:ok, result}` or `max_attempts` attempts have been made. If it exhausts them, return `{:error, failed_step_name, {:retries_exhausted, last_reason}, []}` — note that compensation list is empty, because committed compensable steps are not rolled back once we've crossed the pivot. `last_reason` is the reason from the final attempt.

A few other behaviours I need preserved: steps run strictly in the order they were added, and each action and each compensation sees the accumulated context. A compensating function that raises must not abort the remaining compensations — catch it and record it (the recorded value may be any term). And keep it a plain module with a struct: no GenServer, no processes, no external dependencies.

Give me the complete implementation in a single file.

## The module with `new` missing

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

  def new do
    # TODO
  end

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
      when is_atom(name) and is_function(action_fn, 1) and is_integer(max_attempts) and
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

Output only `new` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
