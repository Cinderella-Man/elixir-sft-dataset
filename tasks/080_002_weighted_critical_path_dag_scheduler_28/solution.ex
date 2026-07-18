  @doc """
  Returns `{:ok, path}`, a list of task ids forming a longest-duration path
  from a source task to a sink task (the chain that determines the makespan).

  Ties are broken deterministically, preferring the smallest task id by term
  ordering.  Returns `{:ok, []}` for an empty graph.
  """
  @spec critical_path(t()) :: {:ok, [id()]}
  def critical_path(%__MODULE__{} = dag) do
    case topo_order(dag) do
      [] ->
        {:ok, []}

      _order ->
        est = compute_est(dag)
        eft = Map.new(est, fn {v, s} -> {v, s + Map.fetch!(dag.durations, v)} end)

        {end_v, _finish} =
          eft
          |> Enum.sort()
          |> Enum.max_by(fn {_v, f} -> f end)

        {:ok, backtrack(dag, est, end_v, [end_v])}
    end
  end