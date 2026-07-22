  defp merge_value(bv, ov, kpath, opts) do
    cond do
      is_map(bv) and is_map(ov) ->
        do_merge(bv, ov, kpath, opts)

      is_list(bv) and is_list(ov) ->
        case list_strategy_for(kpath, opts) do
          :replace -> ov
          :append -> bv ++ ov
        end

      true ->
        ov
    end
  end