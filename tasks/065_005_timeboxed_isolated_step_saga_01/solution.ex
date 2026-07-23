defmodule TimeboxedSaga do
  @moduledoc """
  A saga coordinator that runs each forward action in its own isolated process
  under a per-step deadline.

  Unlike a builder-style coordinator, a saga here is simply a list of step maps
  handed to `run/2` or `run/3`. Each step's forward `:action` runs in a separate,
  monitored process; the coordinator waits for it only up to the step's effective
  deadline. If the deadline is exceeded, the action's process is killed and any
  late reply it might produce is ignored — it can never influence the outcome.

  A `step` is a map with the keys:

    * `:name` — an identifier (any term) used as the context key for the step's
      result and as its label in the error report.
    * `:action` — a 1-arity function receiving the current context, returning
      `{:ok, result}` or `{:error, reason}`.
    * `:compensation` — a 1-arity function receiving the current context that
      undoes the step.
    * `:timeout` — *optional* per-step deadline in milliseconds. When absent, the
      saga's `:default_timeout` applies.

  Only forward actions are timeboxed and isolated; compensations run inline in the
  coordinator process, best-effort, in reverse completion order.
  """

  @type context :: map()
  @type step :: map()
  @type error :: %{
          step: term(),
          error: term(),
          compensated: [term()],
          compensations: map()
        }

  @default_timeout 5000

  @doc """
  Runs `steps` starting from `context`, using default options.

  Equivalent to `run(steps, context, [])`.
  """
  @spec run([step()], context()) :: {:ok, context()} | {:error, error()}
  def run(steps, context), do: run(steps, context, [])

  @doc """
  Runs the list of `steps` in order, starting from `context`.

  Options:

    * `:default_timeout` — deadline in milliseconds applied to any step lacking
      its own `:timeout`. Defaults to `5000`.

  Returns `{:ok, final_context}` when all steps succeed, or `{:error, error}`
  (with `:step`, `:error`, `:compensated`, and `:compensations` keys) when a step
  fails and completed steps are compensated.
  """
  @spec run([step()], context(), keyword()) :: {:ok, context()} | {:error, error()}
  def run(steps, context, opts) do
    default_timeout = Keyword.get(opts, :default_timeout, @default_timeout)
    forward(steps, context, default_timeout, [])
  end

  # --- Forward pass -------------------------------------------------------

  @spec forward([step()], context(), non_neg_integer(), [step()]) ::
          {:ok, context()} | {:error, error()}
  defp forward([], context, _default_timeout, _completed), do: {:ok, context}

  defp forward([step | rest], context, default_timeout, completed) do
    timeout = Map.get(step, :timeout) || default_timeout

    case run_action(step.action, context, timeout) do
      {:ok, result} ->
        new_context = Map.put(context, step.name, result)
        forward(rest, new_context, default_timeout, [step | completed])

      {:error, reason} ->
        compensate(step.name, reason, context, completed)

      {:crashed, reason} ->
        compensate(step.name, {:crashed, reason}, context, completed)

      {:bad_return, value} ->
        compensate(step.name, {:bad_return, value}, context, completed)

      :timeout ->
        compensate(step.name, :timeout, context, completed)
    end
  end

  # Runs `action` in an isolated, monitored process with a deadline. Returns one
  # of `{:ok, result}`, `{:error, reason}`, `{:crashed, reason}`,
  # `{:bad_return, value}`, or `:timeout`.
  @spec run_action((context() -> term()), context(), timeout()) ::
          {:ok, term()}
          | {:error, term()}
          | {:crashed, term()}
          | {:bad_return, term()}
          | :timeout
  defp run_action(action, context, timeout) do
    parent = self()
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        outcome =
          try do
            {:returned, action.(context)}
          catch
            _kind, reason -> {:crashed, reason}
          end

        send(parent, {ref, outcome})
      end)

    receive do
      {^ref, outcome} ->
        Process.demonitor(mon, [:flush])
        classify(outcome)

      {:DOWN, ^mon, :process, ^pid, reason} ->
        classify({:crashed, reason})
    after
      timeout ->
        Process.demonitor(mon, [:flush])
        Process.exit(pid, :kill)
        flush(ref)
        :timeout
    end
  end

  @spec classify(term()) ::
          {:ok, term()} | {:error, term()} | {:crashed, term()} | {:bad_return, term()}
  defp classify({:returned, {:ok, result}}), do: {:ok, result}
  defp classify({:returned, {:error, reason}}), do: {:error, reason}
  defp classify({:returned, other}), do: {:bad_return, other}
  defp classify({:crashed, reason}), do: {:crashed, reason}

  # Discards a possibly-in-flight late reply carrying `ref`. Even if one arrives
  # after this, its unique `ref` never matches a future receive, so it is ignored.
  @spec flush(reference()) :: :ok
  defp flush(ref) do
    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end
  end

  # --- Compensation pass --------------------------------------------------

  # `completed` is most-recently-completed first, which is exactly the order in
  # which compensations must run.
  @spec compensate(term(), term(), context(), [step()]) :: {:error, error()}
  defp compensate(failed_name, error, context, completed) do
    {names, comps} =
      Enum.reduce(completed, {[], %{}}, fn step, {names_acc, comps_acc} ->
        value = run_compensation(step.compensation, context)
        {[step.name | names_acc], Map.put(comps_acc, step.name, value)}
      end)

    {:error,
     %{
       step: failed_name,
       error: error,
       compensated: Enum.reverse(names),
       compensations: comps
     }}
  end

  # Best-effort: a raising (or exiting/throwing) compensation is caught and its
  # value recorded as `{:raised, exception}` without aborting the pass.
  @spec run_compensation((context() -> term()), context()) :: term()
  defp run_compensation(compensation, context) do
    try do
      compensation.(context)
    rescue
      exception -> {:raised, exception}
    catch
      _kind, reason -> {:raised, reason}
    end
  end
end
