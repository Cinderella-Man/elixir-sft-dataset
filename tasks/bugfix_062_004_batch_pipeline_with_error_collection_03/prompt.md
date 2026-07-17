# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `Pipeline` that builds linear stage pipelines and runs them over a **batch** of inputs, collecting successes and failures independently instead of halting the whole run on the first error.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`. Stages are stored in insertion order.
- `Pipeline.run(pipeline, inputs)` — `inputs` is a **list** of items. Each item is threaded **independently** through all stages in order. If an item's stage returns `{:error, reason}`, that item halts (its later stages are skipped) and is recorded as a failure, but the batch continues processing the remaining items. Return `{:ok, report}` where `report` is a map:
  - `:successes` — a list of `%{index: non_neg_integer, result: term}` for items that completed every stage, ordered by input index.
  - `:failures` — a list of `%{index: non_neg_integer, stage: atom, reason: term}` for items that halted, ordered by input index.
  - `:stage_stats` — a list, in pipeline stage order, of `%{stage: atom, executions: non_neg_integer, total_duration_us: non_neg_integer}` where `executions` counts how many items actually ran that stage (items that halted earlier never reach it) and `total_duration_us` is the summed `:timer.tc/1` microseconds across those executions.

An empty pipeline treats every item as an immediate success whose `result` is the input itself, and produces an empty `:stage_stats`. An empty `inputs` list yields empty `:successes` and `:failures`, with each stage's `executions` at `0`.

The module must not use a GenServer or any global state — it is a plain Elixir module working in the caller's process. Timing must use `:timer.tc/1` (microsecond resolution). Use only the standard library, no external dependencies. Give me the complete implementation in a single file.

## The buggy module

```elixir
defmodule Pipeline do
  @moduledoc """
  Linear stage pipelines run over a batch of inputs.

  Each input item is threaded independently through the stages. A failing stage
  halts only that item (recording it as a failure); the batch continues with the
  remaining items. The final report separates successes from failures and
  aggregates per-stage execution counts and timing.

  Stage statistics are tracked per pipeline position, so two stages that share a
  name keep independent counters.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type t :: %__MODULE__{stages: [{atom(), stage_fun()}]}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc "Appends a named stage in insertion order."
  @spec stage(t(), atom(), stage_fun()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Runs every item in `inputs` independently through the pipeline, collecting a
  report of `:successes`, `:failures`, and per-stage `:stage_stats`.
  """
  @spec run(t(), [any()]) :: {:ok, map()}
  def run(%__MODULE__{stages: stages}, inputs) when is_list(inputs) do
    indexed_stages = Enum.with_index(stages)

    {successes, failures, stats} =
      inputs
      |> Enum.with_index()
      |> Enum.reduce({[], [], %{}}, fn {input, index}, {succ, fail, stats} ->
        case process_item(indexed_stages, input, stats) do
          {:ok, result, stats2} ->
            {[%{index: index, result: result} | succ], fail, stats2}

          {:ok, name, reason, stats2} ->
            {succ, [%{index: index, stage: name, reason: reason} | fail], stats2}
        end
      end)

    stage_stats =
      Enum.map(indexed_stages, fn {{name, _fun}, position} ->
        stat_entry(name, position, stats)
      end)

    {:ok,
     %{
       successes: Enum.reverse(successes),
       failures: Enum.reverse(failures),
       stage_stats: stage_stats
     }}
  end

  # ---------------------------------------------------------------------------

  defp process_item([], value, stats), do: {:ok, value, stats}

  defp process_item([{{name, fun}, position} | rest], value, stats) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    stats = bump(stats, position, duration)

    case result do
      {:ok, next_value} ->
        process_item(rest, next_value, stats)

      {:error, reason} ->
        {:error, name, reason, stats}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end

  defp bump(stats, position, duration) do
    Map.update(stats, position, {1, duration}, fn {count, total} ->
      {count + 1, total + duration}
    end)
  end

  defp stat_entry(name, position, stats) do
    {executions, total_duration_us} = Map.get(stats, position, {0, 0})
    %{stage: name, executions: executions, total_duration_us: total_duration_us}
  end
end
```

## Failing test report

```
5 of 15 test(s) failed:

  * test a failing item is isolated; others still succeed
      no case clause matching:
      
          {:error, :guard, :bad, %{0 => {2, 0}, 1 => {2, 0}, 2 => {1, 0}}}
      

  * test stage_stats executions reflect early halting
      no case clause matching:
      
          {:error, :guard, :bad, %{0 => {2, 0}, 1 => {2, 0}, 2 => {1, 0}}}
      

  * test an item failing at the first stage records that stage
      no case clause matching:
      
          {:error, :first, :nope, %{0 => {1, 0}}}
      

  * test a halted item never invokes any later stage function
      no case clause matching:
      
          {:error, :guard, :boom, %{0 => {1, 0}}}
      

  (…1 more)
```
