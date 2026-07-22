defp handle_provider(conn, provider, config, store) do
  header_name = Map.fetch!(config, :header)
  secrets = Map.fetch!(config, :secrets)
  prefix = Map.get(config, :prefix, "")

  {:ok, body, conn} = read_body(conn)
  signature = conn |> get_req_header(header_name) |> List.first()

  cond do
    is_nil(signature) or signature == "" ->
      send_json(conn, 401, %{error: "invalid_signature"})

    Signature.verify_any(body, signature, secrets, prefix) != :ok ->
      send_json(conn, 401, %{error: "invalid_signature"})

    true ->
      handle_verified(conn, provider, body, store)
  end
end