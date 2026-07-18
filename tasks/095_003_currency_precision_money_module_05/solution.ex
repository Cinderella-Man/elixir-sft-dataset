  @doc "Returns the minor-unit exponent for a supported currency."
  @spec exponent(atom()) :: non_neg_integer()
  def exponent(currency) do
    case Map.fetch(@exponents, currency) do
      {:ok, exp} -> exp
      :error -> raise ArgumentError, "unsupported currency: #{inspect(currency)}"
    end
  end