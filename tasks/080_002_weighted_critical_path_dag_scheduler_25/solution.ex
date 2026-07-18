  @doc """
  Returns `{:ok, map}` where `map` is `%{id => earliest_start_time}`.

  A task's earliest start is the maximum over its direct predecessors of
  `(predecessor's earliest start + predecessor's duration)`, or `0` when it
  has no predecessors.
  """
  @spec earliest_start(t()) :: {:ok, %{id() => number()}}
  def earliest_start(%__MODULE__{} = dag) do
    {:ok, compute_est(dag)}
  end