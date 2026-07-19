  @spec apply_coupon(%Cart{}, map()) ::
          {:ok, %Cart{}}
          | {:error, :invalid_coupon | :already_applied | :below_minimum}