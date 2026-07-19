# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `take_caveats` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CapabilityToken` that implements
**attenuable capability tokens** (macaroon-style) — bearer tokens that
anyone holding them can *narrow* offline, without the signing key, but
that nobody can *widen*.

There is no server, no database, and no stored state: a token is a
self-contained binary, and verification is a pure recomputation from the
root key.

## Public API

- `CapabilityToken.mint(root_key, identifier)` — `root_key` is a binary
  signing key, `identifier` is a binary naming the capability (e.g.
  `"user:42"`). Returns a URL-safe binary token with zero caveats.

- `CapabilityToken.attenuate(token, caveat)` — appends one caveat to a
  token **without needing the root key**. `caveat` is a non-empty binary
  (1..65_535 bytes). Returns `{:ok, new_token}`. Returns
  `{:error, :malformed}` if `token` is not a decodable token, if `token`
  or `caveat` is not a binary, or if `caveat` is empty or longer than
  65_535 bytes. The original token is unchanged (tokens are immutable
  binaries); the new token carries the old caveats in order, followed by
  the new one.

- `CapabilityToken.inspect_token(token)` — decodes a token **without any
  key and without checking the signature**. Returns
  `{:ok, %{identifier: identifier, caveats: caveats}}` where `caveats` is
  the list of caveat binaries in the order they were attached, or
  `{:error, :malformed}` if the token cannot be decoded (including for
  non-binary input). This is a debugging/introspection helper — it makes
  no authenticity claim whatsoever.

- `CapabilityToken.authorize(token, root_key, context)` — the real check.
  `context` is a map describing the request being authorized. Returns
  `:ok` if the token's signature chain verifies under `root_key` **and**
  every caveat is satisfied by `context`. Otherwise returns
  `{:error, reason}` (see below).

## Wire format

Build the decoded binary exactly like this (all integers big-endian,
unsigned), then `Base.url_encode64/2` it with `padding: false` so the
token is URL-safe and contains no `+`, `/`, or `=`:

    <<1,                              # version byte, always 1
      id_size::16, identifier::binary-size(id_size),
      caveat_count::16,
      # caveat_count repetitions of:
      #   <<len::16, caveat::binary-size(len)>>
      signature::binary-32>>

So the signature is always the trailing 32 bytes of the decoded binary.

## Signature chain

The signature is an HMAC-SHA256 chain in which each caveat re-keys the
MAC with the previous signature:

    sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
    sig_i = :crypto.mac(:hmac, :sha256, sig_{i-1}, caveat_i)

The token carries only the final signature `sig_n`. This is what makes
attenuation keyless (you can extend the chain from the signature you
hold) while forgery stays impossible (you cannot walk the chain
backwards to drop, reorder, or edit a caveat — doing so requires the
root key). `authorize/3` recomputes the whole chain from `root_key` and
the token's own identifier + caveats and compares the result to the
carried signature **in constant time** (no short-circuit on the first
differing byte).

## Caveat language

A caveat is a binary of the form `"key = value"` — a key, then a space,
an equals sign, and a space, then the value (the value may itself
contain spaces or `=`; only the first `" = "` separates). Exactly three
keys are recognized:

- `"expires_at = <integer>"` — satisfied iff `context[:now]` is an
  integer and `context[:now] < <integer>`. Strictly less: at exactly the
  expiry second the caveat is **not** satisfied. The value must parse as
  a complete integer (leading `-` allowed, trailing garbage not).
- `"action = <string>"` — satisfied iff `context[:action]` is exactly
  equal to `<string>` (binary equality).
- `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is
  a binary that starts with `<string>`.

Everything else **fails closed**: an unrecognized key, a caveat with no
`" = "` separator, a non-integer `expires_at` value, or a context that
is missing the key a caveat needs — all count as *not satisfied*. Never
treat an unknown caveat as vacuously true.

## Check order and error values inside `authorize/3`

Exactly this order:

1. base64 decode → structural parse (version byte, sizes, caveat count,
   exactly 32 trailing signature bytes). Any failure here, or a
   non-binary token / non-binary root key / non-map context, yields
   `{:error, :malformed}`.
2. signature chain verification → mismatch yields
   `{:error, :invalid_signature}`.
3. caveats, evaluated in attachment order → the **first** unsatisfied
   caveat yields `{:error, {:caveat_failed, caveat}}`, where `caveat` is
   that caveat's exact binary. Later caveats are not evaluated.

Signature verification always precedes caveat evaluation, so a token
that is both expired and signed with the wrong key reports
`:invalid_signature`, never `{:caveat_failed, _}`.

## Implementation requirements

- `:crypto.mac/4` with SHA-256 for every link of the chain.
- `Base.url_encode64/2` / `Base.url_decode64/2` with `padding: false`.
- Constant-time signature comparison.
- No external dependencies — Elixir standard library and OTP only.
- No process state, no ETS, no files.

Give me the complete module in a single file.

## The module with `take_caveats` missing

```elixir
defmodule CapabilityToken do
  @moduledoc """
  Attenuable, macaroon-style capability tokens.

  A token is a self-contained, URL-safe binary that names a capability (an
  *identifier*) and carries an ordered list of *caveats* narrowing what the
  bearer may do. Anyone holding a token can **narrow** it offline — appending a
  caveat requires no key — but nobody can **widen** it: dropping, reordering or
  editing a caveat would require walking the HMAC chain backwards, which is
  infeasible without the root key.

  ## Wire format

  All integers are big-endian unsigned. The decoded binary is:

      <<1,                              # version byte
        id_size::16, identifier::binary-size(id_size),
        caveat_count::16,
        # caveat_count repetitions of <<len::16, caveat::binary-size(len)>>
        signature::binary-32>>

  and the token itself is that binary under `Base.url_encode64/2` with
  `padding: false`.

  ## Signature chain

      sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
      sig_i = :crypto.mac(:hmac, :sha256, sig_(i-1), caveat_i)

  Only the final signature travels with the token. `authorize/3` recomputes the
  whole chain from the root key and compares in constant time.

  ## Caveat language

  A caveat is `"key = value"` (the first `" = "` separates; the value may itself
  contain spaces or `=`). Three keys are recognized:

    * `"expires_at = <integer>"` — needs integer `context[:now]`, satisfied iff
      `now < integer` (strictly).
    * `"action = <string>"` — satisfied iff `context[:action] == <string>`.
    * `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is a
      binary starting with `<string>`.

  Anything else fails closed: unknown keys, malformed caveats, non-integer
  expiries and missing context keys are all *not satisfied*.
  """

  @version 1
  @sig_size 32
  @max_caveat_size 65_535

  @type token :: binary()
  @type caveat :: binary()
  @type context :: %{optional(atom()) => term()}
  @type reason :: :malformed | :invalid_signature | {:caveat_failed, caveat()}

  @doc """
  Mints a fresh token for `identifier`, signed with `root_key` and carrying no
  caveats.

  Returns the URL-safe token binary.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> CapabilityToken.inspect_token(token)
      {:ok, %{identifier: "user:42", caveats: []}}
  """
  @spec mint(binary(), binary()) :: token()
  def mint(root_key, identifier) when is_binary(root_key) and is_binary(identifier) do
    signature = :crypto.mac(:hmac, :sha256, root_key, identifier)
    encode(identifier, [], signature)
  end

  @doc """
  Appends `caveat` to `token` without needing the root key.

  Returns `{:ok, new_token}` whose caveats are the old ones, in order, followed
  by `caveat`. Returns `{:error, :malformed}` if `token` is not decodable, if
  either argument is not a binary, or if `caveat` is empty or longer than
  #{@max_caveat_size} bytes. The original token is untouched.
  """
  @spec attenuate(token(), caveat()) :: {:ok, token()} | {:error, :malformed}
  def attenuate(token, caveat)
      when is_binary(token) and is_binary(caveat) and byte_size(caveat) in 1..@max_caveat_size do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      new_signature = :crypto.mac(:hmac, :sha256, signature, caveat)
      {:ok, encode(identifier, caveats ++ [caveat], new_signature)}
    end
  end

  def attenuate(_token, _caveat), do: {:error, :malformed}

  @doc """
  Decodes a token without any key and **without verifying the signature**.

  Returns `{:ok, %{identifier: identifier, caveats: caveats}}` with the caveats
  in attachment order, or `{:error, :malformed}`. This is a debugging helper: it
  makes no authenticity claim at all.
  """
  @spec inspect_token(token()) ::
          {:ok, %{identifier: binary(), caveats: [caveat()]}} | {:error, :malformed}
  def inspect_token(token) when is_binary(token) do
    with {:ok, identifier, caveats, _signature} <- decode(token) do
      {:ok, %{identifier: identifier, caveats: caveats}}
    end
  end

  def inspect_token(_token), do: {:error, :malformed}

  @doc """
  Authorizes `token` under `root_key` for the request described by `context`.

  Returns `:ok` when the signature chain verifies *and* every caveat is
  satisfied. Checks run in this order:

    1. structural decode — `{:error, :malformed}`;
    2. signature chain — `{:error, :invalid_signature}`;
    3. caveats, in attachment order — `{:error, {:caveat_failed, caveat}}` for
       the first unsatisfied one (later caveats are not evaluated).

  Signature verification always precedes caveat evaluation, so a token that is
  both expired and forged reports `:invalid_signature`.
  """
  @spec authorize(token(), binary(), context()) :: :ok | {:error, reason()}
  def authorize(token, root_key, context)
      when is_binary(token) and is_binary(root_key) and is_map(context) do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      expected = chain(root_key, identifier, caveats)

      if secure_compare(expected, signature) do
        check_caveats(caveats, context)
      else
        {:error, :invalid_signature}
      end
    end
  end

  def authorize(_token, _root_key, _context), do: {:error, :malformed}

  # --- encoding -------------------------------------------------------------

  @spec encode(binary(), [caveat()], binary()) :: token()
  defp encode(identifier, caveats, signature) do
    body =
      for caveat <- caveats, into: <<>> do
        <<byte_size(caveat)::16, caveat::binary>>
      end

    binary =
      <<@version, byte_size(identifier)::16, identifier::binary, length(caveats)::16,
        body::binary, signature::binary-size(@sig_size)>>

    Base.url_encode64(binary, padding: false)
  end

  @spec decode(binary()) :: {:ok, binary(), [caveat()], binary()} | {:error, :malformed}
  defp decode(token) do
    with {:ok, binary} <- Base.url_decode64(token, padding: false),
         <<@version, id_size::16, identifier::binary-size(id_size), count::16, rest::binary>> <-
           binary,
         {:ok, caveats, <<signature::binary-size(@sig_size)>>} <- take_caveats(count, rest, []) do
      {:ok, identifier, caveats, signature}
    else
      _other -> {:error, :malformed}
    end
  end

  @spec take_caveats(non_neg_integer(), binary(), [caveat()]) ::
          {:ok, [caveat()], binary()} | :error
  defp take_caveats(0, rest, acc) do
    # TODO
  end

  # --- signatures -----------------------------------------------------------

  @spec chain(binary(), binary(), [caveat()]) :: binary()
  defp chain(root_key, identifier, caveats) do
    Enum.reduce(caveats, :crypto.mac(:hmac, :sha256, root_key, identifier), fn caveat, sig ->
      :crypto.mac(:hmac, :sha256, sig, caveat)
    end)
  end

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  # --- caveats --------------------------------------------------------------

  @spec check_caveats([caveat()], context()) :: :ok | {:error, {:caveat_failed, caveat()}}
  defp check_caveats([], _context), do: :ok

  defp check_caveats([caveat | rest], context) do
    if satisfied?(caveat, context) do
      check_caveats(rest, context)
    else
      {:error, {:caveat_failed, caveat}}
    end
  end

  @spec satisfied?(caveat(), context()) :: boolean()
  defp satisfied?(caveat, context) do
    case :binary.split(caveat, " = ") do
      [key, value] -> satisfied?(key, value, context)
      _other -> false
    end
  end

  @spec satisfied?(binary(), binary(), context()) :: boolean()
  defp satisfied?("expires_at", value, context) do
    with {:ok, limit} <- parse_integer(value),
         now when is_integer(now) <- Map.get(context, :now) do
      now < limit
    else
      _other -> false
    end
  end

  defp satisfied?("action", value, context), do: Map.get(context, :action) === value

  defp satisfied?("resource_prefix", value, context) do
    case Map.get(context, :resource) do
      resource when is_binary(resource) -> String.starts_with?(resource, value)
      _other -> false
    end
  end

  defp satisfied?(_key, _value, _context), do: false

  @spec parse_integer(binary()) :: {:ok, integer()} | :error
  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end
end
```

Give me only the complete implementation of `take_caveats` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
