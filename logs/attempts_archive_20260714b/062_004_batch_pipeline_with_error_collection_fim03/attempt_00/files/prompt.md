Implement the private `bump/3` helper for the `Pipeline` module.

`bump/3` accumulates per-stage execution statistics. It receives:
- `stats` — a map keyed by stage name (an atom). Each value is a two-element tuple `{count, total_duration}`, where `count` is how many times that stage has run so far and `total_duration` is the summed `:timer.tc/1` microseconds across those runs.
- `name` — the atom name of the stage that just executed.
- `duration` — the microsecond duration of this single execution.

It must return the updated `stats` map. If `name` is not yet present in `stats`, insert it with the tuple `{1, duration}` (this was its first execution). If `name` is already present with `{count, total}`, replace it with `{count + 1, total + duration}` — incrementing the execution count by one and adding this run's duration to the running total. No other keys in `stats` are touched.

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

  defp process_item([], value, stats), do: {:ok, value, stats}

  defp process_item([{name, fun} | rest], value, stats) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    stats = bump(stats, name, duration)

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

  defp bump(stats, name, duration) do
    # TODO
  end

  defp stat_entry(name, stats) do
    {executions, total_duration_us} = Map.get(stats, name, {0, 0})
    %{stage: name, executions: executions, total_duration_us: total_duration_us}
  end
end
```