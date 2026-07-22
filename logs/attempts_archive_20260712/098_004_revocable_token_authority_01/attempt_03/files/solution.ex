defmodule TokenAuthority do
  @moduledoc """
  A `GenServer` that issues and validates signed, expiring tokens with support
  for revocation.

  The base HMAC-token design is stateless and can never take a token back. This
  authority keeps a small amount of in-process state — the signing secret and a
  set of revoked token ids ("jtis") — so an operator can invalidate an
  individual outstanding token before it expires.

  Each issued token carries a cryptographically random jti. A token is accepted
  by `verify/2` only if it is well-formed, correctly signed by this authority's
  secret, not expired, and its jti has not been revoked.

  ## Token layout

  The signed region is a length-framed binary:

      <<jti_len::16, jti::binary, issued_at::64, expires_at::64,
        payload_len::32, payload::binary>>

  followed by a trailing 32-byte HMAC-SHA256 tag over that whole region. The
  concatenation is `Base.url_encode64/2`-encoded without padding so the result
  is safe to embed in URLs and headers.
  """

  use GenServer

  @mac_size 32

  @typedoc "A running authority: a pid or registered name."
  @type server :: GenServer.server()

  @typedoc "Errors returned by `verify/2`."
  @type verify_error :: :malformed | :invalid_signature | :expired | :revoked

  @doc """
  Start a `TokenAuthority`.

  `opts` accepts:

    * `:secret` (required) — a binary HMAC signing key.
    * `:clock` (optional) — a zero-arity function returning a Unix epoch second;
      defaults to reading `System.os_time(:second)`. This is a test seam.
    * `:name` (optional) — a name under which to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Issue a token for `payload` valid for `ttl_seconds` seconds.

  Returns `{:ok, token, jti}` where `token` is a URL-safe binary and `jti` is the
  opaque token id you pass to `revoke/2` to later invalidate this token.
  """
  @spec issue(server(), term(), pos_integer()) :: {:ok, binary(), binary()}
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  @doc """
  Decode and validate `token`.

  Returns `{:ok, payload}` when the token is well-formed, correctly signed by
  this authority, not expired, and not revoked. Otherwise returns one of
  `{:error, :malformed}`, `{:error, :invalid_signature}`, `{:error, :expired}`,
  or `{:error, :revoked}`.
  """
  @spec verify(server(), term()) :: {:ok, term()} | {:error, verify_error()}
  def verify(server, token) do
    GenServer.call(server, {:verify, token})
  end

  @doc """
  Mark `jti` as revoked.

  Idempotent; revoking a jti that was never issued simply adds it to the revoked
  set. Once revoked, every token carrying `jti` fails `verify/2` with
  `{:error, :revoked}`.
  """
  @spec revoke(server(), binary()) :: :ok
  def revoke(server, jti) when is_binary(jti) do
    GenServer.call(server, {:revoke, jti})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    secret = validate_secret(Keyword.fetch!(opts, :secret))
    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)
    {:ok, %{secret: secret, clock: clock, revoked: MapSet.new()}}
  end

  @impl true
  def handle_call({:issue, payload, ttl}, _from, state) do
    now = state.clock.()
    jti = :crypto.strong_rand_bytes(16)
    payload_bin = :erlang.term_to_binary(payload)
    token = build_token(state.secret, jti, payload_bin, now, now + ttl)
    {:reply, {:ok, token, jti}, state}
  end

  def handle_call({:verify, token}, _from, state) do
    {:reply, do_verify(state, token), state}
  end

  def handle_call({:revoke, jti}, _from, state) do
    {:reply, :ok, %{state | revoked: MapSet.put(state.revoked, jti)}}
  end

  ## Internal helpers

  defp validate_secret(secret) when is_binary(secret), do: secret

  defp validate_secret(_secret) do
    raise ArgumentError, ":secret must be a binary"
  end

  defp build_token(secret, jti, payload_bin, issued_at, expires_at) do
    jti_len = byte_size(jti)
    payload_len = byte_size(payload_bin)

    signed =
      <<jti_len::16, jti::binary, issued_at::64, expires_at::64, payload_len::32,
        payload_bin::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, signed)
    Base.url_encode64(signed <> mac, padding: false)
  end

  defp do_verify(state, token) when is_binary(token) do
    with {:ok, raw} <- base64_decode(token),
         {:ok, signed, mac} <- split_mac(raw),
         {:ok, jti, _issued_at, expires_at, payload_bin} <- parse(signed) do
      verify_signed(state, signed, mac, jti, expires_at, payload_bin)
    end
  end

  defp do_verify(_state, _token), do: {:error, :malformed}

  defp verify_signed(state, signed, mac, jti, expires_at, payload_bin) do
    expected = :crypto.mac(:hmac, :sha256, state.secret, signed)

    cond do
      not secure_compare(mac, expected) -> {:error, :invalid_signature}
      not (state.clock.() < expires_at) -> {:error, :expired}
      MapSet.member?(state.revoked, jti) -> {:error, :revoked}
      true -> deserialize(payload_bin)
    end
  end

  defp base64_decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end

  defp split_mac(raw) when byte_size(raw) >= @mac_size do
    size = byte_size(raw) - @mac_size
    <<signed::binary-size(size), mac::binary-size(@mac_size)>> = raw
    {:ok, signed, mac}
  end

  defp split_mac(_raw), do: {:error, :malformed}

  defp parse(<<jti_len::16, rest::binary>>) do
    case rest do
      <<jti::binary-size(jti_len), issued_at::64, expires_at::64, payload_len::32,
        payload::binary-size(payload_len)>> ->
        {:ok, jti, issued_at, expires_at, payload}

      _other ->
        {:error, :malformed}
    end
  end

  defp parse(_other), do: {:error, :malformed}

  defp deserialize(payload_bin) do
    {:ok, :erlang.binary_to_term(payload_bin, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time MAC comparison. `:crypto.hash_equals/2` requires equal-length
  # inputs, so mismatched lengths short-circuit to `false` (a signature failure)
  # before the constant-time check runs.
  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp secure_compare(_a, _b), do: false
end
