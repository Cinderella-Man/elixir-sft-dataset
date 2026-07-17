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