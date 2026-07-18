# Bring this working module up to house style

I asked for the following:

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

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  defstruct steps: []

  @doc "Creates a new, empty saga."
  def new, do: %__MODULE__{}

  @doc "Appends a named step."
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga from the beginning."
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context, [])
  end

  @doc "Resumes execution from a previously produced journal."
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

  defp compensate_all(completed, context, jrev0) do
    Enum.reduce(completed, {[], jrev0}, fn %{name: name, compensate: compensate}, {acc, jrev} ->
      value = safe_compensate(compensate, context)
      {acc ++ [{name, value}], [{:compensated, name, value} | jrev]}
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

The style review said:

```
The solution is green but does not meet the house style: no @spec on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/070_004_resumable_journaled_saga_01/attempt_0 -->
