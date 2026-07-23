# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

**Ticket:** Implement `Pipeline` — a single-file Elixir module for building and running linear processing pipelines from composable stages, where each stage carries its own **retry policy**.

**Public API — `Pipeline.new()`**
- Returns a fresh, empty pipeline struct.

**Public API — `Pipeline.stage(pipeline, name, fun, opts \\ [])`**
- Appends a named stage to the pipeline.
- `name` is an atom.
- `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`.
- Enforce both with guard clauses: calling `stage/4` with a non-atom `name`, or with a `fun` whose arity is not 1, must raise `FunctionClauseError`.
- `opts` may contain:
  - `:retries` — non-negative integer; the number of *additional* attempts allowed after the first attempt fails. Default `0` (no retries).
  - `:backoff_ms` — non-negative integer number of milliseconds to sleep between attempts. Default `0`.
- Stages are stored in insertion order.
- The same `name` may be used more than once; each such stage is kept and executed as its own step, in insertion order.

**Public API — `Pipeline.run(pipeline, input)`**
- Executes all stages in order, threading the result of each successful stage as the input to the next.
- Empty pipeline returns `{:ok, input, []}` — input unchanged, empty metadata.
- On `{:error, reason}` from a stage that still has retries remaining: re-invoke the same stage on the **same input** (after sleeping `:backoff_ms`), up to its retry budget.
- If a stage eventually succeeds within its budget, continue with the next stage.
- If a stage exhausts its retry budget: immediately halt and return `{:error, failed_stage_name, reason, attempts}`, where `attempts` is the total number of times that stage was invoked (initial try + retries used). Do not execute any subsequent stages.
- If every stage ultimately succeeds: return `{:ok, final_result, metadata}`, where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer, attempts: pos_integer}` entries in execution order.
- `duration_us` is the **total** time spent across all attempts of that stage; `attempts` is how many times its function ran.

**Timing**
- Measure with `:timer.tc/1` (or equivalent microsecond-resolution call).
- Accumulate across attempts.

**Constraints**
- No GenServer, no global state — plain Elixir module running in the caller's process (`Process.sleep/1` for backoff is fine).
- Standard library only; no external dependencies.
- Deliver the complete implementation in a single file.

## The buggy module

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
      when is_atom(name) and is_function(fun, 2) and is_list(opts) do
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

## Failing test report

```
9 of 11 test(s) failed:

  * test single successful stage with no retries has attempts: 1
      no function clause matching in Pipeline.stage/4

  * test three stages thread results in order
      no function clause matching in Pipeline.stage/4

  * test a flaky stage succeeds after retries and reports attempts
      no function clause matching in Pipeline.stage/4

  * test exhausting the retry budget halts with the attempts count
      no function clause matching in Pipeline.stage/4

  (…5 more)
```
