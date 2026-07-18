  @doc """
  Returns `{:ok, number}`, the total project duration: the maximum
  earliest-finish over all tasks.  Returns `{:ok, 0}` for an empty graph.
  """
  @spec makespan(t()) :: {:ok, number()}
  def makespan(%__MODULE__{} = dag) do
    span =
      dag
      |> compute_est()
      |> Enum.map(fn {v, s} -> s + Map.fetch!(dag.durations, v) end)
      |> case do
        [] -> 0
        finishes -> Enum.max(finishes)
      end

    {:ok, span}
  end