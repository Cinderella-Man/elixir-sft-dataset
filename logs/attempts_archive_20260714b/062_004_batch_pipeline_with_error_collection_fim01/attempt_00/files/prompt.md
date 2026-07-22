Implement the private `process_item/3` function.

`process_item/3` threads a single input item through the pipeline's stages,
one stage at a time, while accumulating per-stage timing/execution statistics.
It takes three arguments: the remaining list of `{name, fun}` stages, the
current `value`, and a `stats` map (keyed by stage name, holding
`{execution_count, total_duration_us}` tuples).

Its behavior:

- **Base case — no stages left:** the item has cleared every stage. Return
  `{:ok, value, stats}`, where `value` is the final threaded result and `stats`
  is passed through unchanged.
- **Recursive case — at least one `{name, fun}` stage remains:** run that stage,
  measuring it with `:timer.tc/1` wrapped around `fun.(value)` so you capture
  both the elapsed microseconds (`duration`) and the stage's return value. Fold
  that `duration` into the statistics for `name` using the existing `bump/3`
  helper, producing the updated `stats`. Then dispatch on the stage's return:
  - `{:ok, next_value}` — the stage succeeded; continue by recursing over the
    remaining stages with `next_value` and the updated `stats`.
  - `{:error, reason}` — the item halts here. Return
    `{:error, name, reason, stats}` (using the updated `stats`) so the caller can
    record which stage failed and why, and skip the remaining stages.
  - anything else — the stage violated its contract. Raise an `ArgumentError`
    with a message of the form
    `"stage <inspected name> returned an invalid value: <inspected value>."`.

In every case the accumulated `stats` (including the just-run stage) must be
threaded onward so that execution counts and durations are never lost, even when
an item halts.

```elixir
defmodule Pipeline do
  @moduledoc """
  Linear stage pipelines run over a batch of inputs.

  Each input item is threaded independently through the stages. A failing stage
  halts only that item (recording it as a failure); the batch continues with the
  remaining items. The final report separates successes from failures and
  aggregates per-stage execution counts and timing.
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
    {successes, failures, stats} =
      inputs
      |> Enum.with_index()
      |> Enum.reduce({[], [], %{}}, fn {input, index}, {succ, fail, stats} ->
        case process_item(stages, input, stats) do
          {:ok, result, stats2} ->
            {[%{index: index, result: result} | succ], fail, stats2}

          {:error, name, reason, stats2} ->
            {succ, [%{index: index, stage: name, reason: reason} | fail], stats2}
        end
      end)

    stage_stats = Enum.map(stages, fn {name, _fun} -> stat_entry(name, stats) end)

    {:ok,
     %{
       successes: Enum.reverse(successes),
       failures: Enum.reverse(failures),
       stage_stats: stage_stats
     }}
  end

  # ---------------------------------------------------------------------------

  defp process_item(stages, value, stats) do
    # TODO
  end

  defp bump(stats, name, duration) do
    Map.update(stats, name, {1, duration}, fn {count, total} ->
      {count + 1, total + duration}
    end)
  end

  defp stat_entry(name, stats) do
    {executions, total_duration_us} = Map.get(stats, name, {0, 0})
    %{stage: name, executions: executions, total_duration_us: total_duration_us}
  end
end
```