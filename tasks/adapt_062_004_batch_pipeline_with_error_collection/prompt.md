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

I need a module from you called `Pipeline` — the idea is that it builds linear stage pipelines and then runs them over a **batch** of inputs, collecting successes and failures independently rather than halting the whole run the moment one input errors out.

Here's the public API I'm after. `Pipeline.new()` just hands back a fresh, empty pipeline struct. `Pipeline.stage(pipeline, name, fun)` appends a named stage to it, where `name` is an atom and `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`; keep the stages in insertion order. I want invalid arguments rejected outright — a non-atom `name`, or a `fun` whose arity is not one, should blow up with a `FunctionClauseError`, and I'd like that enforced with guard clauses rather than manual checks.

Then `Pipeline.run(pipeline, inputs)` does the work. `inputs` is a **list** of items, and a non-list `inputs` has to raise a `FunctionClauseError` too (again, enforce it with a guard). Each item gets threaded **independently** through all the stages in order. If a stage returns `{:error, reason}` for some item, that item halts right there — its later stages are skipped — and it's recorded as a failure, but the batch keeps right on processing the remaining items. The return value is `{:ok, report}` where `report` is a map with three keys.

`:successes` is a list of `%{index: non_neg_integer, result: term}` covering the items that made it through every stage, ordered by input index. `:failures` is a list of `%{index: non_neg_integer, stage: atom, reason: term}` for the items that halted, also ordered by input index. And `:stage_stats` is a list in pipeline stage order with **one entry per stage position** — so if two stages happen to share a `name`, they still keep independent counters — each entry looking like `%{stage: atom, executions: non_neg_integer, total_duration_us: non_neg_integer}`, where `executions` counts how many items actually ran that stage (items that halted earlier never reach it) and `total_duration_us` is the summed `:timer.tc/1` microseconds across those executions.

A couple of edge cases I care about: an empty pipeline should treat every item as an immediate success whose `result` is the input itself, and produce an empty `:stage_stats`. An empty `inputs` list should yield empty `:successes` and `:failures`, with each stage's `executions` at `0` and `total_duration_us` at `0`.

One more thing — no GenServer, no global state of any kind. This is a plain Elixir module doing its work in the caller's process. Timing has to go through `:timer.tc/1` (microsecond resolution). Standard library only, no external dependencies. Send me the complete implementation in a single file.
