defmodule Saga do
  @moduledoc """
  A composable implementation of the Saga pattern with **nested sub-sagas**.

  A saga is an ordered list of steps. Each step is either:

    * a **leaf** — a plain action paired with a compensating function, or
    * a **nested** step — an entire embedded `Saga` value.

  This makes a saga a *tree* of actions. Forward execution runs the steps in
  order, threading an accumulated context (a map) through them. On success each
  step merges its result into the context under its `name`.

  When any leaf fails, forward execution stops and every previously completed
  step of the *current* saga is compensated in reverse order. A nested sub-saga
  first unwinds its own completed inner steps, then the failure propagates
  outward and the outer saga unwinds its completed steps. Compensation therefore
  walks the whole tree back out in the exact reverse of the order things
  happened.

  Compensating functions never fail the chain: their return values are recorded,
  and if one raises, the exception is caught and recorded as
  `{:exception, exception, stacktrace}` so that the remaining compensations still
  run.

  The module is a plain struct — no processes, no GenServer, no dependencies.
  """

  @typedoc "The accumulated context threaded through the saga."
  @type context :: map()

  @typedoc "The name (key) under which a step's result is stored."
  @type name :: atom()

  @typedoc "A leaf action: receives the context, returns success or failure."
  @type action_fn :: (context() -> {:ok, any()} | {:error, any()})

  @typedoc "A compensating function: receives the context, return value recorded."
  @type compensate_fn :: (context() -> any())

  @typedoc "An internal step description."
  @type step ::
          {:leaf, name(), action_fn(), compensate_fn()}
          | {:nested, name(), t()}

  @typedoc "The path (outermost to failing leaf) of a failure."
  @type failed_path :: [name()]

  @typedoc "Recorded compensation results, a keyword list in reverse call order."
  @type compensation_results :: [{name(), any()}]

  @typedoc "A saga value."
  @type t :: %__MODULE__{steps: [step()]}

  defstruct steps: []

  # A completed-step record, retained so the step can be compensated later.
  @typep record ::
           {:leaf, name(), compensate_fn()}
           | {:nested, name(), [record()]}

  @doc """
  Creates a new, empty saga.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a **leaf** step to `saga`.

  `action_fn` receives the accumulated context and must return `{:ok, result}`
  or `{:error, reason}`. On success `result` is merged into the context under
  `name`. `compensate_fn` receives the context; its return value is recorded but
  can never fail the chain.
  """
  @spec step(t(), name(), action_fn(), compensate_fn()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    append(saga, {:leaf, name, action_fn, compensate_fn})
  end

  @doc """
  Appends a **nested** step whose behaviour is another `Saga`.

  When executed, `sub_saga` runs against the current accumulated context; on
  success its final context is merged into the outer context under `name`.
  """
  @spec nest(t(), name(), t()) :: t()
  def nest(%__MODULE__{} = saga, name, %__MODULE__{} = sub_saga) do
    append(saga, {:nested, name, sub_saga})
  end

  @doc """
  Runs the steps of `saga` in order against `context`.

  Returns `{:ok, final_context}` on full success, or
  `{:error, failed_path, reason, compensation_results}` on failure, where
  `failed_path` names the steps from the outermost saga down to the leaf that
  actually failed and `compensation_results` is a keyword list in reverse call
  order (nested entries hold their own reversed keyword list).
  """
  @spec execute(t(), context()) ::
          {:ok, context()}
          | {:error, failed_path(), any(), compensation_results()}
  def execute(%__MODULE__{} = saga, context \\ %{}) do
    case run(saga, context) do
      {:ok, final_context, _completed} -> {:ok, final_context}
      {:error, _path, _reason, _comp} = error -> error
    end
  end

  # --- internal execution -------------------------------------------------

  @spec append(t(), step()) :: t()
  defp append(%__MODULE__{steps: steps} = saga, step) do
    %{saga | steps: steps ++ [step]}
  end

  # Runs a saga, returning either success with the forward-ordered completed
  # records, or a failure carrying the path, reason and compensation results.
  @spec run(t(), context()) ::
          {:ok, context(), [record()]}
          | {:error, failed_path(), any(), compensation_results()}
  defp run(%__MODULE__{steps: steps}, context) do
    run_steps(steps, context, [])
  end

  # `completed` is kept in reverse order (most recent first) so it is already
  # in the correct order for compensation.
  @spec run_steps([step()], context(), [record()]) ::
          {:ok, context(), [record()]}
          | {:error, failed_path(), any(), compensation_results()}
  defp run_steps([], context, completed) do
    {:ok, context, Enum.reverse(completed)}
  end

  defp run_steps([step | rest], context, completed) do
    case run_step(step, context) do
      {:ok, new_context, record} ->
        run_steps(rest, new_context, [record | completed])

      {:error, path, reason, step_comp} ->
        {:error, path, reason, step_comp ++ compensate(completed, context)}
    end
  end

  # Runs a single step. On failure `step_comp` is the failed step's own
  # contribution to the compensation results ([] for a leaf whose action
  # failed, `[{name, inner}]` for a nested sub-saga that unwound itself).
  @spec run_step(step(), context()) ::
          {:ok, context(), record()}
          | {:error, failed_path(), any(), compensation_results()}
  defp run_step({:leaf, name, action_fn, compensate_fn}, context) do
    case action_fn.(context) do
      {:ok, result} ->
        {:ok, Map.put(context, name, result), {:leaf, name, compensate_fn}}

      {:error, reason} ->
        {:error, [name], reason, []}
    end
  end

  defp run_step({:nested, name, sub_saga}, context) do
    case run(sub_saga, context) do
      {:ok, final_context, inner_records} ->
        {:ok, Map.put(context, name, final_context), {:nested, name, inner_records}}

      {:error, inner_path, reason, inner_comp} ->
        {:error, [name | inner_path], reason, [{name, inner_comp}]}
    end
  end

  # --- compensation -------------------------------------------------------

  # `records` are given in the order they must be compensated (reverse of the
  # order in which they completed).
  @spec compensate([record()], context()) :: compensation_results()
  defp compensate(records, context) do
    Enum.map(records, &compensate_one(&1, context))
  end

  @spec compensate_one(record(), context()) :: {name(), any()}
  defp compensate_one({:leaf, name, compensate_fn}, context) do
    {name, safe_compensate(compensate_fn, context)}
  end

  defp compensate_one({:nested, name, inner_records}, context) do
    {name, compensate(Enum.reverse(inner_records), context)}
  end

  # Runs a compensating function, capturing a raise as a recordable value
  # rather than letting it abort the remaining compensations.
  @spec safe_compensate(compensate_fn(), context()) :: any()
  defp safe_compensate(compensate_fn, context) do
    try do
      compensate_fn.(context)
    rescue
      exception -> {:exception, exception, __STACKTRACE__}
    end
  end
end