  defp validate_variants(variants) do
    Enum.each(variants, fn
      {name, weight} when is_atom(name) and is_integer(weight) and weight >= 0 ->
        :ok

      other ->
        raise ArgumentError, "invalid variant spec: #{inspect(other)}"
    end)

    total = Enum.reduce(variants, 0, fn {_name, weight}, acc -> acc + weight end)

    unless total == 100 do
      raise ArgumentError, "variant weights must sum to 100, got #{total}"
    end

    variants
  end