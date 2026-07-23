# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `step` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

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

## The module with `step` missing

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with a **durable journal** and **crash-resumable execution**.

  Each run emits a chronological list of events — `{:completed, name, result}`,
  `{:failed, name, reason}`, `{:compensated, name, value}` — returned alongside
  the usual result. `resume/3` rebuilds state from such a journal, skipping the
  actions of steps that already completed and continuing with the rest. A
  failure during a resumed run rolls back every completed step (replayed and
  newly run alike) in reverse order.
  """

  @typedoc "An accumulated context passed to every action and compensation."
  @type context :: map()

  @typedoc "The result an action function must return."
  @type action_result :: {:ok, term()} | {:error, term()}

  @typedoc "A single named step in the saga definition."
  @type step_entry :: %{
          name: atom(),
          action: (context() -> action_result()),
          compensate: (context() -> term())
        }

  @typedoc "A single chronological journal event."
  @type event ::
          {:completed, atom(), term()}
          | {:failed, atom(), term()}
          | {:compensated, atom(), term()}

  @typedoc "An ordered, chronological list of journal events."
  @type journal :: [event()]

  @typedoc "The saga struct holding an ordered list of steps."
  @type t :: %__MODULE__{steps: [step_entry()]}

  @typedoc "The value returned by `execute/2` and `resume/3`."
  @type run_result ::
          {:ok, context(), journal()}
          | {:error, atom(), term(), keyword(), journal()}

  defstruct steps: []

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    # TODO
  end

  @doc "Executes the saga from the beginning."
  @spec execute(t(), context()) :: run_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context, [])
  end

  @doc "Resumes execution from a previously produced journal."
  @spec resume(t(), context(), journal()) :: run_result()
  def resume(%__MODULE__{steps: steps}, context, journal)
      when is_map(context) and is_list(journal) do
    completed_names =
      for {:completed, name, _result} <- journal, do: name

    context2 =
      Enum.reduce(journal, context, fn
        {:completed, name, result}, acc -> Map.put(acc, name, result)
        _other, acc -> acc
      end)

    {done_steps, remaining} =
      Enum.split_with(steps, fn step -> step.name in completed_names end)

    # Seed the reverse-accumulator journal with the completed events so the
    # returned journal stays chronological once reversed.
    jrev0 =
      journal
      |> Enum.filter(fn
        {:completed, _n, _r} -> true
        _ -> false
      end)
      |> Enum.reverse()

    run(remaining, Enum.reverse(done_steps), context2, jrev0)
  end

  # --- execution -----------------------------------------------------------
  #
  # `completed` is in reverse-execution order (most recent first).
  # `jrev` is the journal accumulated in reverse (most recent event first).

  @spec run([step_entry()], [step_entry()], context(), journal()) :: run_result()
  defp run([], _completed, context, jrev), do: {:ok, context, Enum.reverse(jrev)}

  defp run([%{name: name, action: action} = step | rest], completed, context, jrev) do
    case safe(action, context) do
      {:ok, result} ->
        run(
          rest,
          [step | completed],
          Map.put(context, name, result),
          [{:completed, name, result} | jrev]
        )

      {:error, reason} ->
        {comp, jrev2} = compensate_all(completed, context, [{:failed, name, reason} | jrev])
        {:error, name, reason, comp, Enum.reverse(jrev2)}
    end
  end

  @spec safe((context() -> term()), context()) :: action_result()
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

  @spec compensate_all([step_entry()], context(), journal()) :: {keyword(), journal()}
  defp compensate_all(completed, context, jrev0) do
    Enum.reduce(completed, {[], jrev0}, fn %{name: name, compensate: compensate}, {acc, jrev} ->
      value = safe_compensate(compensate, context)
      {acc ++ [{name, value}], [{:compensated, name, value} | jrev]}
    end)
  end

  @spec safe_compensate((context() -> term()), context()) :: term()
  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```

Reply with `step` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
