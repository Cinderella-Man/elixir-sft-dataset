# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule BloomFilter do
  @enforce_keys [:m, :k, :bits]
  defstruct [:m, :k, :bits]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)

    # Represent bits as a tuple of integers where each integer is used as a
    # 64-bit word.  This gives O(1) element access via `elem/2`.
    num_words = ceil(m / 64)
    bits = Tuple.duplicate(0, num_words)

    %__MODULE__{m: m, k: k, bits: bits}
  end

  def add(%__MODULE__{m: m, k: k, bits: bits} = filter, item) do
    new_bits =
      Enum.reduce(0..(k - 1), bits, fn seed, acc ->
        bit_index = hash(item, seed, m)
        set_bit(acc, bit_index)
      end)

    %{filter | bits: new_bits}
  end

  def member?(%__MODULE__{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      bit_index = hash(item, seed, m)
      get_bit(bits, bit_index) == 1
    end)
  end

  def merge(%__MODULE__{m: m, k: k} = f1, %__MODULE__{m: m, k: k} = f2) do
    merged_bits =
      f1.bits
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(f2.bits))
      |> Enum.map(fn {w1, w2} -> Bitwise.bor(w1, w2) end)
      |> List.to_tuple()

    %{f1 | bits: merged_bits}
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; " <>
            "filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Optimal bit-array size:
  #   m = -ceil( n * ln(p) / (ln 2)^2 )
  @ln2 :math.log(2)

  defp optimal_m(n, p) do
    ceil(-n * :math.log(p) / (@ln2 * @ln2))
  end

  # Optimal number of hash functions:
  #   k = round( (m / n) * ln 2 )
  defp optimal_k(m, n) do
    max(1, round(m / n * @ln2))
  end

  # Derive k independent hash values from a single hash primitive by hashing
  # the tuple {seed, item}.  :erlang.phash2/2 accepts any Erlang term and
  # returns a non-negative integer in 0..range-1.
  defp hash(item, seed, m) do
    :erlang.phash2({seed, item}, m)
  end

  # Each "word" in the `bits` tuple holds 64 bits.
  defp word_index(bit_index), do: div(bit_index, 64)
  defp bit_offset(bit_index), do: rem(bit_index, 64)

  defp set_bit(bits, bit_index) do
    wi = word_index(bit_index)
    bo = bit_offset(bit_index)
    word = elem(bits, wi)
    put_elem(bits, wi, Bitwise.bor(word, Bitwise.bsl(1, bo)))
  end

  defp get_bit(bits, bit_index) do
    wi = word_index(bit_index)
    bo = bit_offset(bit_index)
    word = elem(bits, wi)
    Bitwise.band(Bitwise.bsr(word, bo), 1)
  end
end
```
