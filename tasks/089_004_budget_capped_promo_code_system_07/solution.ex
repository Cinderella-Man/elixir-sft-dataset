  @doc "Creates a budget-capped promo code from `attrs`. Returns `{:ok, code}` or error."
  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})