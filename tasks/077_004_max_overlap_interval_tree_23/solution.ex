  @doc """
  Returns the number of stored intervals whose closed range contains `point`.
  """
  @spec depth_at(t(), integer()) :: number()
  def depth_at(tree, point), do: prefix_sum(tree, point)