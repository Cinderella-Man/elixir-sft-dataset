# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

I need a module from you called `Pipeline` — the idea is that it builds linear stage pipelines and then runs them over a **batch** of inputs, collecting successes and failures independently rather than halting the whole run the moment one input errors out.

Here's the public API I'm after. `Pipeline.new()` just hands back a fresh, empty pipeline struct. `Pipeline.stage(pipeline, name, fun)` appends a named stage to it, where `name` is an atom and `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`; keep the stages in insertion order. I want invalid arguments rejected outright — a non-atom `name`, or a `fun` whose arity is not one, should blow up with a `FunctionClauseError`, and I'd like that enforced with guard clauses rather than manual checks.

Then `Pipeline.run(pipeline, inputs)` does the work. `inputs` is a **list** of items, and a non-list `inputs` has to raise a `FunctionClauseError` too (again, enforce it with a guard). Each item gets threaded **independently** through all the stages in order. If a stage returns `{:error, reason}` for some item, that item halts right there — its later stages are skipped — and it's recorded as a failure, but the batch keeps right on processing the remaining items. The return value is `{:ok, report}` where `report` is a map with three keys.

`:successes` is a list of `%{index: non_neg_integer, result: term}` covering the items that made it through every stage, ordered by input index. `:failures` is a list of `%{index: non_neg_integer, stage: atom, reason: term}` for the items that halted, also ordered by input index. And `:stage_stats` is a list in pipeline stage order with **one entry per stage position** — so if two stages happen to share a `name`, they still keep independent counters — each entry looking like `%{stage: atom, executions: non_neg_integer, total_duration_us: non_neg_integer}`, where `executions` counts how many items actually ran that stage (items that halted earlier never reach it) and `total_duration_us` is the summed `:timer.tc/1` microseconds across those executions.

A couple of edge cases I care about: an empty pipeline should treat every item as an immediate success whose `result` is the input itself, and produce an empty `:stage_stats`. An empty `inputs` list should yield empty `:successes` and `:failures`, with each stage's `executions` at `0` and `total_duration_us` at `0`.

One more thing — no GenServer, no global state of any kind. This is a plain Elixir module doing its work in the caller's process. Timing has to go through `:timer.tc/1` (microsecond resolution). Standard library only, no external dependencies. Send me the complete implementation in a single file.

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
