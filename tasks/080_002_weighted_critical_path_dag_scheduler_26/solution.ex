  @doc """
  Returns `{:ok, map}` where each value is `earliest_start + duration`.
  """
  @spec earliest_finish(t()) :: {:ok, %{id() => number()}}
  def earliest_finish(%__MODULE__{} = dag) do
    est = compute_est(dag)
    eft = Map.new(est, fn {v, s} -> {v, s + Map.fetch!(dag.durations, v)} end)
    {:ok, eft}
  end