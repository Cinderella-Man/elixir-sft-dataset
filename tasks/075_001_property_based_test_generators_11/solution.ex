  @doc """
  Produces maps representing a monetary value.

  ## Shape

      %{
        amount:   non_neg_integer(),  # cents, 0–10_000_000
        currency: String.t()          # "USD" | "EUR" | "GBP" | "JPY" | "CHF"
      }
  """
  @spec money() :: StreamData.t(map())
  def money do
    SD.fixed_map(%{
      amount: SD.integer(0..10_000_000),
      currency: SD.member_of(["USD", "EUR", "GBP", "JPY", "CHF"])
    })
  end