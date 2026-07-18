  @doc "Creates a new, empty cart with an optional `:tax_rate`."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{tax_rate: Keyword.get(opts, :tax_rate, 0.0), items: %{}, coupons: []}
  end