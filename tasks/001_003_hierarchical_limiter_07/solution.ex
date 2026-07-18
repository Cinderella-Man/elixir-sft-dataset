  defp validate_tiers!(tiers) do
    Enum.each(tiers, fn
      {name, max, window}
      when is_atom(name) and is_integer(max) and max > 0 and
             is_integer(window) and window > 0 ->
        :ok

      bad ->
        raise ArgumentError,
              "invalid tier #{inspect(bad)} — expected {atom, pos_integer, pos_integer}"
    end)

    :ok
  end