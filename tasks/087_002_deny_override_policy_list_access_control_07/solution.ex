  @doc """
  Returns `true` when `evaluate/4` yields `:allow`, `false` otherwise.
  """
  @spec authorized?(atom(), atom(), atom(), [statement()]) :: boolean()
  def authorized?(role, resource, action, policies) do
    evaluate(role, resource, action, policies) == :allow
  end