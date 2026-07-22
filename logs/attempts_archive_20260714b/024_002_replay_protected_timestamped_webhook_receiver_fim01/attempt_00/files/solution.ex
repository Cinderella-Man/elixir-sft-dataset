defp verify_signed(header, body, secret, now, tolerance) do
  parsed = if is_binary(header) and header != "", do: Signature.parse(header), else: %{}

  with %{"t" => ts_str, "v1" => v1} <- parsed,
       {ts, ""} <- Integer.parse(ts_str) do
    cond do
      abs(now - ts) > tolerance ->
        {:error, :expired}

      Plug.Crypto.secure_compare(Signature.sign(ts, body, secret), v1) ->
        :ok

      true ->
        {:error, :invalid}
    end
  else
    _ -> {:error, :invalid}
  end
end