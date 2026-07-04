  @spec enabled?(atom()) :: boolean()
  def enabled?(flag) do
    case record(flag) do
      nil -> false
      {state, prereqs} -> state_on?(state) and Enum.all?(prereqs, &enabled?/1)
    end
  end