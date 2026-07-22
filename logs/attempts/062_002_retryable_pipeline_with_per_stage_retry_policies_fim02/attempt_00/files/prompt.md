Implement the private `execute/3` function. It drives the pipeline recursively:
its arguments are the remaining list of stages, the current value being threaded
through the pipeline, and an accumulator of stage metadata built up in reverse
order (most recent first).

When there are no stages left, the pipeline has fully succeeded: return
`{:ok, value, metadata}` where `metadata` is the accumulator restored to execution
order (i.e. reversed).

Otherwise, run the first stage against the current value using `run_stage/2`. If it
succeeds with `{:ok, next_value, meta}`, prepend `meta` to the accumulator and
continue executing the remaining stages with `next_value`. If it fails with
`{:error, name, reason, attempts}` (the stage exhausted its retry budget), halt
immediately and return that same error tuple without touching any remaining stages.

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear processing pipelines with per-stage retry policies.

  Each stage may declare a retry budget (`:retries`) and a backoff
  (`:backoff_ms`). A failing stage is re-invoked on the same input until it
  succeeds or the budget is exhausted. Timing is accumulated across attempts.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type stage_meta :: %{
          stage: atom(),
          duration_us: non_neg_integer(),
          attempts: pos_integer()
        }
  @type t :: %__MODULE__{stages: [{atom(), stage_fun(), non_neg_integer(), non_neg_integer()}]}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc """
  Appends a named stage with an optional retry policy.

  Options:
    * `:retries` — additional attempts after the first failure (default `0`)
    * `:backoff_ms` — milliseconds slept between attempts (default `0`)
  """
  @spec stage(t(), atom(), stage_fun(), keyword()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    retries = Keyword.get(opts, :retries, 0)
    backoff = Keyword.get(opts, :backoff_ms, 0)
    %__MODULE__{pipeline | stages: stages ++ [{name, fun, retries, backoff}]}
  end

  @doc """
  Executes all stages in order, retrying failing stages per their policy.

  Returns `{:ok, final_result, metadata}` on full success, or
  `{:error, failed_stage, reason, attempts}` when a stage exhausts its budget.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [stage_meta()]}
          | {:error, atom(), any(), pos_integer()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------

  defp execute(stages, value, meta_acc) do
    # TODO
  end

  defp run_stage({name, fun, retries, backoff}, value) do
    attempt(name, fun, value, retries, backoff, 0, 0)
  end

  defp attempt(name, fun, value, retries_left, backoff, attempts_before, dur_acc) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    attempts = attempts_before + 1
    total_dur = dur_acc + duration

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: total_dur, attempts: attempts}}

      {:error, reason} ->
        if retries_left > 0 do
          if backoff > 0, do: Process.sleep(backoff)
          attempt(name, fun, value, retries_left - 1, backoff, attempts, total_dur)
        else
          {:error, name, reason, attempts}
        end

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}. " <>
                "Expected {:ok, result} or {:error, reason}."
    end
  end
end
```