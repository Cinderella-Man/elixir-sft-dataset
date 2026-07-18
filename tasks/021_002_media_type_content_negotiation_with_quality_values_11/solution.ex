  @doc """
  Negotiates the API version from the `Accept` header and assigns it, or halts
  with `406` when no supported version is acceptable.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    supported = Keyword.get(opts, :supported, ["v1", "v2"])
    default = Keyword.get(opts, :default, "v2")

    case get_req_header(conn, "accept") do
      [] -> assign(conn, :api_version, default)
      [accept | _] -> resolve(conn, accept, supported, default)
    end
  end