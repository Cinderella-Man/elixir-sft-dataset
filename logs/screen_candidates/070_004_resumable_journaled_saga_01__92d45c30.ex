defmodule Saga do
  @moduledoc """
  A plain-struct implementation of the Saga pattern with a durable journal and
  crash-resumable execution.

  A saga is an ordered list of named steps. Each step has an *action* function and a
  *compensating* function. Actions run strictly in order, each receiving the context
  accumulated so far. When an action succeeds its result is merged into the context under
  the step's name; when it fails, every previously completed step is compensated in reverse
  order.

  ## Journal

  Every run emits an ordered event journal — a list of events in chronological order:

    * `{:completed, name, result}` — the step's action returned `{:ok, result}`.
    * `{:failed, name, reason}` — the step's action returned `{:error, reason}`.
    * `{:compensated, name, value}` — a completed step's compensation ran, returning `value`.
      If the compensating function raised, `value` is `{:exception, exception, stacktrace}`.

  The journal is durable in the sense that it fully describes the progress of a run: a
  partially-completed run can be handed back to `resume/3`, which rebuilds the context from
  the journal's `{:completed, name, result}` events *without* re-invoking those actions, and
  then continues with the remaining steps.

  ## Example

      iex> saga =
      ...>   Saga.new()
      ...>   |> Saga.step(:charge, fn _ctx -> {:ok, %{id: 1}} end, fn _ctx -> :refunded end)
      ...>   |> Saga.step(:ship, fn ctx -> {:error, {:no_stock, ctx.charge.id}} end, fn _ -> :ok end)
      iex> {:error, :ship, {:no_stock, 1}, comps, journal} = Saga.execute(saga, %{})
      iex> comps
      [charge: :refunded]
      iex> journal
      [{:completed, :charge, %{id: 1}}, {:failed, :ship, {:no_stock, 1}},
       {:compensated, :charge, :refunded}]
  """

  @typedoc "The name of a step."
  @type name :: atom()

  @typedoc "The accumulated context passed to every action and compensating function."
  @type context :: map()

  @typedoc "A step's action function."
  @type action_fun :: (context() -> {:ok, term()} | {:error, term()})

  @typedoc "A step's compensating function. Its return value is recorded, never checked."
  @type compensate_fun :: (context() -> term())

  @typedoc "A single journal event, in chronological order relative to its siblings."
  @type event ::
          {:completed, name(), term()}
          | {:failed, name(), term()}
          | {:compensated, name(), term()}

  @typedoc "An ordered list of journal events."
  @type journal :: [event()]

  @typedoc "Compensation results in reverse call order."
  @type compensation_results :: keyword()

  @typedoc "A single saga step."
  @type step :: %{name: name(), action: action_fun(), compensate: compensate_fun()}

  @type t :: %__MODULE__{steps: [step()]}

  defstruct steps: []

  @doc """
  Creates a new, empty saga.

      iex> Saga.new()
      %Saga{steps: []}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Appends a named step to the saga.

  `action_fn` receives the accumulated context and must return `{:ok, result}` or
  `{:error, reason}`; on success `result` is merged into the context under `name`.

  `compensate_fn` receives the context and may return anything — its value is recorded in
  the journal and in the compensation results but never fails the chain. If it raises, the
  exception is caught and recorded as `{:exception, exception, stacktrace}`.
  """
  @spec step(t(), name(), action_fun(), compensate_fun()) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    %{saga | steps: steps ++ [%{name: name, action: action_fn, compensate: compensate_fn}]}
  end

  @doc """
  Runs every step of the saga from the beginning, starting from `context`.

  Returns `{:ok, final_context, journal}` when all steps succeed, or
  `{:error, failed_step_name, reason, compensation_results, journal}` when a step fails —
  where `compensation_results` is a keyword list `[step_name: value]` in reverse call order
  and `journal` is the complete chronological event list.
  """
  @spec execute(t(), context()) ::
          {:ok, context(), journal()}
          | {:error, name(), term(), compensation_results(), journal()}
  def execute(%__MODULE__{} = saga, context) when is_map(context) do
    run(saga.steps, context, [], [])
  end

  @doc """
  Resumes a saga from a previously produced `journal`.

  The context is reconstructed by merging every `{:completed, name, result}` event of
  `journal` into `context` under `name`, *without* re-invoking those actions. The remaining
  steps (assumed to be the suffix following the completed prefix) are then run, appending
  new events to the journal's completed events so the returned journal stays chronological.

  If a later step fails, *all* completed steps — those replayed from the journal and those
  newly run — are compensated in reverse order using the saga definition's compensating
  functions. An empty journal makes this behave exactly like `execute/2`.
  """
  @spec resume(t(), context(), journal()) ::
          {:ok, context(), journal()}
          | {:error, name(), term(), compensation_results(), journal()}
  def resume(%__MODULE__{} = saga, context, journal) when is_map(context) and is_list(journal) do
    completed = for {:completed, name, result} <- journal, do: {name, result}
    context = Enum.reduce(completed, context, fn {name, result}, acc -> merge(acc, name, result) end)

    done_names = Enum.map(completed, fn {name, _result} -> name end)
    done_set = MapSet.new(done_names)

    remaining = Enum.reject(saga.steps, fn step -> MapSet.member?(done_set, step.name) end)
    replayed_events = Enum.map(completed, fn {name, result} -> {:completed, name, result} end)

    # `run/4` keeps its completed-step stack in reverse order, so seed it with the replayed
    # steps reversed — that makes compensation walk newest-to-oldest across both sets.
    replayed_steps =
      done_names
      |> Enum.map(fn name -> Enum.find(saga.steps, &(&1.name == name)) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reverse()

    run(remaining, context, replayed_steps, Enum.reverse(replayed_events))
  end

  # `done` is the stack of completed steps, newest first.
  # `events` is the journal built so far, newest first.
  @spec run([step()], context(), [step()], journal()) ::
          {:ok, context(), journal()}
          | {:error, name(), term(), compensation_results(), journal()}
  defp run([], context, _done, events), do: {:ok, context, Enum.reverse(events)}

  defp run([step | rest], context, done, events) do
    case step.action.(context) do
      {:ok, result} ->
        context = merge(context, step.name, result)
        run(rest, context, [step | done], [{:completed, step.name, result} | events])

      {:error, reason} ->
        events = [{:failed, step.name, reason} | events]
        {results, events} = compensate_all(done, context, events)
        {:error, step.name, reason, results, Enum.reverse(events)}
    end
  end

  # Walks the completed-step stack newest-first, so results come back in reverse call order.
  @spec compensate_all([step()], context(), journal()) :: {compensation_results(), journal()}
  defp compensate_all(done, context, events) do
    Enum.reduce(done, {[], events}, fn step, {results, events} ->
      value = safely_compensate(step, context)
      {results ++ [{step.name, value}], [{:compensated, step.name, value} | events]}
    end)
  end

  @spec safely_compensate(step(), context()) :: term()
  defp safely_compensate(step, context) do
    step.compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  end

  @spec merge(context(), name(), term()) :: context()
  defp merge(context, name, result), do: Map.put(context, name, result)
end