  @doc """
  Reads the `authorization` header, expecting `Bearer <token>`.

  On success assigns `:current_user`; otherwise halts with a 401 JSON body.
  """
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = resolve_store(conn, opts)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case TeamStore.get_user_by_token(store, token) do
          {:ok, user_id} -> assign(conn, :current_user, user_id)
          :error -> unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end