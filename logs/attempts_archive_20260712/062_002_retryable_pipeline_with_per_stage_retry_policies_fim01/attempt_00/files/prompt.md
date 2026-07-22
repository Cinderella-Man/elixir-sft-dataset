# Task: Implement `attempt/7`

Implement the private recursive helper `attempt/7`, the core of the pipeline's
retry loop for a single stage.

`attempt(name, fun, value, retries_left, backoff, attempts_before, dur_acc)`
runs one attempt of the stage function and then decides whether to retry.

It must:

1. Invoke `fun.(value)` while measuring its execution time with `:timer.tc/1`,
   capturing both the microsecond `duration` and the `result`.
2. Compute the running totals for this stage: the attempt count is
   `attempts_before + 1`, and the accumulated duration is `dur_acc + duration`.
3. Branch on `result`:
   - On `{:ok, next_value}` — the stage succeeded. Return
     `{:ok, next_value, meta}` where `meta` is
     `%{stage: name, duration_us: total_dur, attempts: attempts}` using the
     accumulated duration and attempt count.
   - On `{:error, reason}` — the stage failed.
     - If `retries_left > 0`, there is still budget: sleep for `backoff`
       milliseconds via `Process.sleep/1` **only when `backoff > 0`**, then
       recurse into `attempt/7` on the **same `value`**, decrementing
       `retries_left` by 1 and threading through the updated attempt count and
       accumulated duration.
     - If no retries remain, halt this stage and return
       `{:error, name, reason, attempts}` with the total number of attempts made.
   - On any other value — raise an `ArgumentError` explaining that the stage
     `name` returned an invalid value and that `{:ok, result}` or
     `{:error, reason}` was expected.

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

  defp execute([], value, meta_acc), do: {:ok, value, Enum.reverse(meta_acc)}

  defp execute([stage | rest], value, meta_acc) do
    case run_stage(stage, value) do
      {:ok, next_value, meta} -> execute(rest, next_value, [meta | meta_acc])
      {:error, name, reason, attempts} -> {:error, name, reason, attempts}
    end
  end

  defp run_stage({name, fun, retries, backoff}, value) do
    attempt(name, fun, value, retries, backoff, 0, 0)
  end

  defp attempt(name, fun, value, retries_left, backoff, attempts_before, dur_acc) do
    # TODO
  end
end
```