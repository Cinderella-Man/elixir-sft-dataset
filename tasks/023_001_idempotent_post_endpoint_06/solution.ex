  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end