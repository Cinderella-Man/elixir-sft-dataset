# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`step/4` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `step/4`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `step/4` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
