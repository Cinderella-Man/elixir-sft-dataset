defp merge_value(bv, ov, kpath, opts) do
  cond do
    locked?(kpath, opts) and bv != ov ->
      {bv, [%{type: :locked_violation, path: kpath, base: bv, override: ov}]}

    locked?(kpath, opts) ->
      {bv, []}

    is_map(bv) and is_map(ov) ->
      do_merge(bv, ov, kpath, opts)

    is_list(bv) and is_list(ov) ->
      case list_strategy_for(kpath, opts) do
        :replace -> {ov, []}
        :append -> {bv ++ ov, []}
      end

    opts.strict and type_kind(bv) != type_kind(ov) ->
      {ov, [%{type: :type_mismatch, path: kpath, base: bv, override: ov}]}

    true ->
      {ov, []}
  end
end