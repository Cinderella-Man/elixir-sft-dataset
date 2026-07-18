  defp price_match?(p, params) do
    min_ok =
      case parse_price(Map.get(params, "min_price")) do
        {:ok, cents} -> p.price_cents >= cents
        :error -> true
      end

    max_ok =
      case parse_price(Map.get(params, "max_price")) do
        {:ok, cents} -> p.price_cents <= cents
        :error -> true
      end

    min_ok and max_ok
  end