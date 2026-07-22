  @spec variant_for(atom(), term()) :: atom()
  def variant_for(flag_name, user_id) do
    case lookup(flag_name) do
      {:on} -> :on
      {:off} -> :off
      {:variants, variants} -> pick_variant(flag_name, user_id, variants)
      nil -> :off
    end
  end