  @doc """
  Returns `true` if at least one copy of `interval` is stored in `tree`.
  """
  @spec member?(t(), interval()) :: boolean()
  def member?(tree, {_s, _f} = interval), do: do_member?(tree, interval)