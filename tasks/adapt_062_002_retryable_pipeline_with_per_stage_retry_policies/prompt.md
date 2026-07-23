# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear processing pipelines.

  Stages are executed in insertion order, each receiving the previous stage's
  result as input. Timing metadata (in microseconds) is collected for every
  stage that actually runs.

  ## Example

      iex> Pipeline.new()
      ...> |> Pipeline.stage(:parse,    fn s -> {:ok, String.to_integer(s)} end)
      ...> |> Pipeline.stage(:double,   fn n -> {:ok, n * 2} end)
      ...> |> Pipeline.stage(:to_str,   fn n -> {:ok, Integer.to_string(n)} end)
      ...> |> Pipeline.run("21")
      {:ok, "42", [
        %{stage: :parse,   duration_us: ...},
        %{stage: :double,  duration_us: ...},
        %{stage: :to_str,  duration_us: ...}
      ]}
  """

  @enforce_keys [:stages]
  defstruct stages: []

  @type stage_meta :: %{stage: atom(), duration_us: non_neg_integer()}

  @type t :: %__MODULE__{
          stages: [{atom(), (any() -> {:ok, any()} | {:error, any()})}]
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc """
  Appends a named stage to the pipeline.

  `fun` must be a one-arity function that returns either
  `{:ok, result}` or `{:error, reason}`.
  """
  @spec stage(t(), atom(), (any() -> {:ok, any()} | {:error, any()})) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Executes all stages in insertion order, threading results through the chain.

  Returns:
  - `{:ok, final_result, [%{stage: atom, duration_us: non_neg_integer}]}` — all stages passed.
  - `{:error, failed_stage, reason}` — a stage failed; subsequent stages are skipped.

  Timing is measured with `:timer.tc/1` around every stage invocation, but
  metadata travels only in the success tuple — the error result carries no
  metadata list, so a failed run discards the timings collected so far.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [stage_meta()]}
          | {:error, atom(), any()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Base case — all stages completed successfully.
  defp execute([], value, meta_acc) do
    {:ok, value, Enum.reverse(meta_acc)}
  end

  defp execute([{name, fun} | rest], value, meta_acc) do
    {duration_us, result} = :timer.tc(fn -> fun.(value) end)
    meta = %{stage: name, duration_us: duration_us}

    case result do
      {:ok, next_value} ->
        execute(rest, next_value, [meta | meta_acc])

      {:error, reason} ->
        # The contract's halt result is exactly three elements with no
        # metadata list — the timings accumulated so far are dropped.
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}. " <>
                "Expected {:ok, result} or {:error, reason}."
    end
  end
end
```

## New specification

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
