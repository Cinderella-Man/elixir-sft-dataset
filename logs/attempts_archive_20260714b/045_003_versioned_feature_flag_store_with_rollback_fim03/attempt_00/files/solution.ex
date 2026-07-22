def enabled_for?(flag, user_id) do
  case current_state(flag) do
    {:on} -> true
    {:off} -> false
    {:percentage, pct} -> :erlang.phash2({flag, user_id}, 100) < pct
    nil -> false
  end
end