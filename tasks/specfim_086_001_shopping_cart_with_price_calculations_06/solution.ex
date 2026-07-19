  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          tax: float(),
          grand_total: float(),
          items: [map()]
        }