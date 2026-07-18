# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

  Timing is recorded (via `:timer.tc/1`) for every stage that actually ran,
  including the one that failed.
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
        # Return accumulated metadata (in execution order) as part of caller
        # context — exposed via the three-element error tuple if desired, but
        # the public contract only requires the three-element form below.
        # We honour the spec strictly here.
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

Write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines from composable stages, where each stage can carry its own **retry policy**.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun, opts \\ [])` — appends a named stage to the pipeline. `name` is an atom, `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Enforce these with guard clauses: calling `stage/4` with a non-atom `name`, or with a `fun` whose arity is not 1, must raise `FunctionClauseError`. `opts` may contain:
  - `:retries` — a non-negative integer, the number of *additional* attempts allowed after the first attempt fails (default `0`, i.e. no retries).
  - `:backoff_ms` — a non-negative integer number of milliseconds to sleep between attempts (default `0`).
  Stages must be stored in insertion order. The same `name` may be used more than once; each such stage is kept and executed as its own step, in insertion order.
- `Pipeline.run(pipeline, input)` — executes all stages in order, threading the result of each successful stage as the input to the next. Running an empty pipeline returns `{:ok, input, []}` (the input unchanged, with empty metadata).
  - When a stage returns `{:error, reason}` and it still has retries remaining, re-invoke the same stage on the **same input** (after sleeping `:backoff_ms`), up to its retry budget.
  - If a stage eventually succeeds within its budget, continue with the next stage.
  - If a stage exhausts its retry budget, immediately halt and return `{:error, failed_stage_name, reason, attempts}` where `attempts` is the total number of times that stage was invoked (initial try + retries used). Do not execute any subsequent stages.
  - If every stage ultimately succeeds, return `{:ok, final_result, metadata}` where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer, attempts: pos_integer}` entries in execution order. `duration_us` is the **total** time spent across all attempts of that stage; `attempts` is how many times its function ran.

Timing must be measured with `:timer.tc/1` (or equivalent microsecond-resolution call) and accumulated across attempts.

The module must not use a GenServer or any global state — it is a plain Elixir module that works in the caller's process (using `Process.sleep/1` for backoff is fine). Use only the standard library, no external dependencies. Give me the complete implementation in a single file.
