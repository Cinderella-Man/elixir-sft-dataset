  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          tax: float(),
          shipping: float(),
          grand_total: float(),
          items: [map()]
        }