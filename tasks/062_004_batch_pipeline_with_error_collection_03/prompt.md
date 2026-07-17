Implement the public `run/2` function.

`run/2` takes a `%Pipeline{}` (whose `stages` field is a list of `{name, fun}`
tuples in insertion order) and a **list** of `inputs`, and threads each input item
**independently** through all stages in order.

It must:

- Pair each input with its zero-based index (via `Enum.with_index/1`), then fold over
  the items accumulating three things: a list of successes, a list of failures, and a
  per-stage stats map.
- For each item, run it through the stages using the private `process_item/3` helper,
  passing the current stats map so timing/execution counts accumulate across items:
  - On `{:ok, result, stats2}` (the item cleared every stage), prepend
    `%{index: index, result: result}` to the successes accumulator and carry `stats2`
    forward.
  - On `{:error, name, reason, stats2}` (the item halted at a stage), prepend
    `%{index: index, stage: name, reason: reason}` to the failures accumulator and
    carry `stats2` forward.
- After the fold, build `stage_stats` by mapping over the pipeline's stages in order
  and calling the private `stat_entry/2` helper for each stage name, so the result is
  in pipeline stage order and includes stages with zero executions.
- Return `{:ok, report}` where `report` is a map with `:successes` and `:failures`
  reversed back into input-index order, plus the `:stage_stats` list.

The function head must pattern-match `%__MODULE__{stages: stages}` and guard on
`is_list(inputs)`.

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
    # TODO
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