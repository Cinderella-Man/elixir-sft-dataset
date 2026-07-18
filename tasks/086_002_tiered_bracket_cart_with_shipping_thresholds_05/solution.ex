  @doc "Creates a new, empty cart. See the module doc for supported options."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{
      tax_rate: Keyword.get(opts, :tax_rate, 0.0),
      items: %{},
      discount_tiers: Keyword.get(opts, :discount_tiers, @default_tiers),
      shipping_flat: Keyword.get(opts, :shipping_flat, 0.0),
      free_shipping_threshold: Keyword.get(opts, :free_shipping_threshold, nil)
    }
  end