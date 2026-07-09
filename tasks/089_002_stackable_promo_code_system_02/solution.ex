  defp process(codes, order_total, user_id, now, state) do
    {valids, rejected, _seen} =
      Enum.reduce(codes, {[], [], MapSet.new()}, fn cs, {v, r, seen} ->
        if MapSet.member?(seen, cs) do
          {v, [%{code: cs, reason: :duplicate_in_order} | r], seen}
        else
          seen = MapSet.put(seen, cs)

          case check(cs, order_total, user_id, now, state) do
            {:ok, code} -> {[{cs, code} | v], r, seen}
            {:error, reason} -> {v, [%{code: cs, reason: reason} | r], seen}
          end
        end
      end)

    valids = Enum.reverse(valids)
    rejected = Enum.reverse(rejected)

    percentages = Enum.filter(valids, fn {_cs, c} -> c.type == :percentage end)
    shippings = Enum.filter(valids, fn {_cs, c} -> c.type == :free_shipping end)
    fixeds = Enum.filter(valids, fn {_cs, c} -> c.type == :fixed_amount end)

    {chosen_pct, extra_pcts} =
      case percentages do
        [] ->
          {nil, []}

        _ ->
          best = Enum.max_by(percentages, fn {_cs, c} -> c.value end)
          {best, List.delete(percentages, best)}
      end

    {chosen_ship, extra_ships} =
      case shippings do
        [] -> {nil, []}
        [h | t] -> {h, t}
      end

    {remaining, applied} = {order_total, []}

    {remaining, applied} =
      case chosen_pct do
        nil ->
          {remaining, applied}

        {cs, c} ->
          d = min(round(order_total * c.value / 100), remaining)
          {remaining - d, applied ++ [%{code: cs, type: :percentage, discount: d}]}
      end

    {remaining, applied} =
      case chosen_ship do
        nil ->
          {remaining, applied}

        {cs, c} ->
          d = min(c.value, remaining)
          {remaining - d, applied ++ [%{code: cs, type: :free_shipping, discount: d}]}
      end

    {remaining, applied} =
      Enum.reduce(fixeds, {remaining, applied}, fn {cs, c}, {rem, acc} ->
        d = min(c.value, rem)
        {rem - d, acc ++ [%{code: cs, type: :fixed_amount, discount: d}]}
      end)

    new_state =
      Enum.reduce(applied, state, fn %{code: cs}, st -> record_use(st, cs, user_id) end)

    rejected_all =
      rejected ++
        Enum.map(extra_pcts, fn {cs, _c} ->
          %{code: cs, reason: :percentage_already_applied}
        end) ++
        Enum.map(extra_ships, fn {cs, _c} ->
          %{code: cs, reason: :free_shipping_already_applied}
        end)

    result = %{
      total_discount: order_total - remaining,
      final_total: remaining,
      applied: applied,
      rejected: rejected_all
    }

    {result, new_state}
  end