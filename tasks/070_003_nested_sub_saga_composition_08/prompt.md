# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `safe`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# `Saga` — Saga pattern with composable, nested sub-sagas

Implement an Elixir module `Saga` supporting the Saga pattern with composable, nested sub-sagas. A saga step is either a plain leaf action or an entire embedded sub-saga, forming a tree; compensation must unwind that tree correctly.

**Public API**
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a **leaf** step. `action_fn` receives the accumulated context and returns `{:ok, result}` or `{:error, reason}`; on success the result is merged into the context under `name`. `compensate_fn` receives the accumulated context as it stands when compensation runs (including the results of steps that completed before the failure); its return value is recorded but never fails the chain.
- `Saga.nest(saga, name, sub_saga)` — appends a **nested** step whose behaviour is another `Saga` value. When executed, the sub-saga runs against the current accumulated context; on success its final context is merged into the outer context under `name`.
- `Saga.execute(saga, context)` — runs the steps in order.

**Return values**
- `{:ok, final_context}` on full success.
- `{:error, failed_path, reason, compensation_results}` on failure.
- `failed_path` is a list of step names from the outermost saga down to the leaf that actually failed (e.g. `[:child, :y]` when leaf `:y` failed inside nested step `:child`; a top-level leaf failure yields `[:name]`).
- `compensation_results` is a keyword list `[step_name: value]` in reverse call order.

**Failure & compensation semantics**
- Leaf failure: forward execution stops; previously completed steps of the **current** saga are compensated in reverse order.
- Nested sub-saga failure: the sub-saga first compensates its own completed inner steps (in reverse), then the failure propagates to the outer saga, which compensates its previously completed steps. The returned `compensation_results` lists the failed nested step's inner compensation results first, as `{nested_name, inner_keyword_list}`, followed by the outer steps in reverse order.
- Compensation reaching a previously **fully-succeeded** nested step: every inner step is compensated in reverse, and its entry in the keyword list is `{nested_name, inner_keyword_list}` (itself in reverse order).
- Nesting is arbitrarily deep.
- A raising compensating function must not abort the remaining compensations; catch and record it.
- When a compensating function raises, the value recorded for that step in `compensation_results` is `{:exception, exception, stacktrace}` — a 3-tuple carrying the raised exception struct and the stacktrace it was caught with.

**Constraints**
- Plain module with a struct — no GenServer, no processes, no external dependencies.
- Deliver the complete implementation in a single file.

## The module with `safe` missing

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with **composable, nested sub-sagas**.

  A step is either a leaf (an action/compensation pair) or a nested step
  whose behaviour is another `Saga`. Execution and compensation both recurse
  through the resulting tree. Failures carry a `failed_path` describing the
  chain of names from the outermost saga down to the failing leaf.
  """

  defstruct steps: []

  @type t :: %__MODULE__{steps: [map()]}
  @type context :: map()
  @type action_fn :: (context() -> {:ok, term()} | {:error, term()})
  @type compensate_fn :: (context() -> term())
  @type failure :: {:error, [atom()], term(), keyword()}

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a leaf step."
  @spec step(t(), atom(), action_fn(), compensate_fn()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :leaf, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Appends a nested step whose behaviour is another saga."
  @spec nest(t(), atom(), t()) :: t()
  def nest(%__MODULE__{} = saga, name, %__MODULE__{} = sub_saga) when is_atom(name) do
    entry = %{kind: :nested, name: name, saga: sub_saga}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga against an initial context map."
  @spec execute(t(), context()) :: {:ok, context()} | failure()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end

  # --- execution -----------------------------------------------------------

  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :leaf, name: name, action: action, compensate: comp} | rest],
         completed,
         ctx
       ) do
    case safe(action, ctx) do
      {:ok, result} ->
        done = %{kind: :leaf, name: name, compensate: comp}
        run(rest, [done | completed], Map.put(ctx, name, result))

      {:error, reason} ->
        {:error, [name], reason, compensate_all(completed, ctx)}
    end
  end

  defp run([%{kind: :nested, name: name, saga: sub} | rest], completed, ctx) do
    case execute(sub, ctx) do
      {:ok, sub_ctx} ->
        done = %{kind: :nested, name: name, saga: sub, ctx: sub_ctx}
        run(rest, [done | completed], Map.put(ctx, name, sub_ctx))

      {:error, sub_path, reason, sub_comp} ->
        # The sub-saga already unwound its own completed steps; propagate and
        # then compensate this saga's previously completed steps.
        outer = compensate_all(completed, ctx)
        {:error, [name | sub_path], reason, [{name, sub_comp} | outer]}
    end
  end

  defp safe(action, context) do
    # TODO
  end

  # --- compensation --------------------------------------------------------

  # `completed` is in reverse-execution order (most recent first).
  defp compensate_all(completed, ctx) do
    Enum.map(completed, fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub, ctx: sub_ctx} ->
        {name, compensate_full(sub.steps, sub_ctx)}
    end)
  end

  # Compensates a fully-succeeded saga: every step, in reverse order.
  defp compensate_full(steps, ctx) do
    steps
    |> Enum.reverse()
    |> Enum.map(fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub} ->
        {name, compensate_full(sub.steps, Map.get(ctx, name, ctx))}
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

Output only `safe` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
