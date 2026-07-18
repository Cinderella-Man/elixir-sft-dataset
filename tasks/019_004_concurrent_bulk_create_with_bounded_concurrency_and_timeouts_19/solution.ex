  @doc """
  Return the high-water mark of simultaneously-running item tasks.
  """
  @spec peak() :: non_neg_integer()
  def peak, do: Agent.get(__MODULE__, fn %{peak: peak} -> peak end)