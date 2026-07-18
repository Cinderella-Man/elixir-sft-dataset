  @doc "Previews the discount for `code_string` on `order_total` (cents) without recording a use."
  @spec preview(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def preview(code_string, order_total)
      when is_binary(code_string) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:preview, code_string, order_total})
  end