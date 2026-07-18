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

Write me an Elixir module called `Pipeline` that builds linear stage pipelines and runs them over a **batch** of inputs, collecting successes and failures independently instead of halting the whole run on the first error.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`. Stages are stored in insertion order. Reject invalid arguments — a non-atom `name`, or a `fun` whose arity is not one — with a `FunctionClauseError` (enforce this with guard clauses).
- `Pipeline.run(pipeline, inputs)` — `inputs` is a **list** of items; a non-list `inputs` must raise a `FunctionClauseError` (enforce with a guard). Each item is threaded **independently** through all stages in order. If an item's stage returns `{:error, reason}`, that item halts (its later stages are skipped) and is recorded as a failure, but the batch continues processing the remaining items. Return `{:ok, report}` where `report` is a map:
  - `:successes` — a list of `%{index: non_neg_integer, result: term}` for items that completed every stage, ordered by input index.
  - `:failures` — a list of `%{index: non_neg_integer, stage: atom, reason: term}` for items that halted, ordered by input index.
  - `:stage_stats` — a list, in pipeline stage order with **one entry per stage position** (so two stages that share a `name` keep independent counters), of `%{stage: atom, executions: non_neg_integer, total_duration_us: non_neg_integer}` where `executions` counts how many items actually ran that stage (items that halted earlier never reach it) and `total_duration_us` is the summed `:timer.tc/1` microseconds across those executions.

An empty pipeline treats every item as an immediate success whose `result` is the input itself, and produces an empty `:stage_stats`. An empty `inputs` list yields empty `:successes` and `:failures`, with each stage's `executions` at `0` and `total_duration_us` at `0`.

The module must not use a GenServer or any global state — it is a plain Elixir module working in the caller's process. Timing must use `:timer.tc/1` (microsecond resolution). Use only the standard library, no external dependencies. Give me the complete implementation in a single file.
