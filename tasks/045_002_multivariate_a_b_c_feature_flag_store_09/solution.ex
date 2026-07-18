  @doc "Returns `true` only when `flag_name` is globally `:on`."
  @spec enabled?(atom()) :: boolean()
  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:on} -> true
      _ -> false
    end
  end