  @doc "Returns `true` when `variant_for/2` is anything other than `:off`."
  @spec enabled_for?(atom(), term()) :: boolean()
  def enabled_for?(flag_name, user_id), do: variant_for(flag_name, user_id) != :off