  @doc """
  Returns `true` only when `flag`'s current state is `:on`. Unknown flags and
  flags in any other mode return `false`.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag) do
    case current_state(flag) do
      {:on} -> true
      _ -> false
    end
  end