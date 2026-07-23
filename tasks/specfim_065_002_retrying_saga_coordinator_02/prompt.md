# Fill in one @spec

Below: a working module where the `@spec` for
`new/0` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `new/0` missing

```elixir
defmodule RetrySaga do
  @moduledoc """
  A saga / compensating-transaction coordinator with **bounded retries** on each
  step's forward action.

  Steps run in order. A step's action may be retried up to `:max_attempts` times
  (default 1). Only when all attempts return `{:error, _}` is the step considered
  failed, at which point the compensations of previously-completed steps are run in
  reverse completion order (best-effort).
  """

  @opaque t :: %__MODULE__{steps: [step()]}
  @type context :: map()
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term()),
          max_attempts: pos_integer()
        }
  @type error :: %{
          step: term(),
          error: term(),
          attempts: pos_integer(),
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  defstruct steps: []

  @doc "Returns a new, empty saga."
  # TODO: @spec
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step. `opts` supports `:max_attempts` (a positive integer, default 1).
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()),
          keyword()
        ) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_attempts) and max_attempts >= 1 do
      raise ArgumentError,
            "max_attempts must be a positive integer, got: #{inspect(max_attempts)}"
    end

    step = %{name: name, action: action, compensation: compensation, max_attempts: max_attempts}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # `completed` is in reverse completion order (most recent first).
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([step | rest], context, completed) do
    case run_action(step, context, 1) do
      {:ok, result} ->
        forward(rest, Map.put(context, step.name, result), [step | completed])

      {:error, reason, attempts} ->
        compensate(completed, context, step.name, reason, attempts)
    end
  end

  defp run_action(step, context, attempt) do
    case step.action.(context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempt < step.max_attempts do
          run_action(step, context, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end

  defp compensate(completed, context, failed_step, reason, attempts) do
    {compensated, compensations} =
      Enum.reduce(completed, {[], %{}}, fn %{name: name, compensation: comp}, {names, results} ->
        result = comp.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       step: failed_step,
       error: reason,
       attempts: attempts,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```

The `@spec` attribute only — nothing more.
