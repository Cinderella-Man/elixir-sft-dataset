  def enabled_for?(flag, user_id) do
    case record(flag) do
      nil ->
        false

      {state, prereqs} ->
        eval(state, flag, user_id) and Enum.all?(prereqs, &enabled_for?(&1, user_id))
    end
  end