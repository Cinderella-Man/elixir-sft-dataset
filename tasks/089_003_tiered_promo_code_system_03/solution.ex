defp check(cs, order_total, user_id, now, state) do
  with {:ok, code} <- fetch_code(cs, state),
       :ok <- check_not_yet_valid(code, now),
       :ok <- check_expired(code, now),
       {:ok, tier, _index} <- fetch_tier(code, order_total),
       :ok <- check_max_uses(code, cs, state),
       :ok <- check_max_uses_per_user(code, cs, user_id, state) do
    {:ok, code, tier_discount(tier, order_total)}
  end
end