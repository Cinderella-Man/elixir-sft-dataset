# Both values are maps → recurse.
defp merge_values(base_val, override_val, key_path, opts)
     when is_map(base_val) and is_map(override_val) do
  do_merge(base_val, override_val, key_path, opts)
end

# Both values are lists → apply the applicable list strategy.
defp merge_values(base_val, override_val, key_path, opts)
     when is_list(base_val) and is_list(override_val) do
  strategy = list_strategy_for(key_path, opts)

  case strategy do
    :replace -> override_val
    :append  -> base_val ++ override_val
  end
end

# Any other combination (scalar vs scalar, type mismatch, etc.) → override wins.
defp merge_values(_base_val, override_val, _key_path, _opts), do: override_val