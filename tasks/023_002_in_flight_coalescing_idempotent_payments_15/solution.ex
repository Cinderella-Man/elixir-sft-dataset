  @doc """
  Processes a payment, coalescing concurrent in-flight requests that share the
  same `idempotency_key`.

  Returns `{:ok, response}` or `{:error, reason}`. When `idempotency_key` is
  `nil` every call runs the processor independently.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key}, 30_000)
  end