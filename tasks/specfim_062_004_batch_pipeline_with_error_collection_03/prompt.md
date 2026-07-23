# Fill in one @spec

Below: a working module where the `@spec` for
`stage/3` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `stage/3` missing

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
  # TODO: @spec
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

          {:error, name, reason, stats2} ->
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

The `@spec` attribute only — nothing more.
