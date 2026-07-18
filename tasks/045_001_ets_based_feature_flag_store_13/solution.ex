  @doc """
  Returns `true` only when `flag_name` is in the `:on` state.

  Reads directly from ETS — no GenServer round-trip.
  Unknown flags return `false`.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:on} -> true
      _ -> false
    end
  end