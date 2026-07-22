Implement the private `compensate_full/2` function. It compensates a saga whose
every step previously succeeded, producing the compensation results for all of its
steps in **reverse execution order**. Given the saga's `steps` list and the context
`ctx` under which they ran, reverse the steps and map each one to a `{name, value}`
pair: for a leaf step, run its `compensate` function via `safe_compensate/2` against
`ctx` and record the result; for a nested step, recurse with `compensate_full/2` over
the sub-saga's own steps, using the nested context stored under that step's `name`
(`Map.get(ctx, name, ctx)`). The function returns a keyword list `[step_name: value]`
in reverse order, and nesting may be arbitrarily deep.

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
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
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
    # TODO
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