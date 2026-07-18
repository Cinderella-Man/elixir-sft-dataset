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
defmodule ConcurrentBloomFilter do
  @ln2 :math.log(2)

  @enforce_keys [:m, :k, :ref]
  defstruct [:m, :k, :ref]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = max(1, ceil(-expected_size * :math.log(false_positive_rate) / (@ln2 * @ln2)))
    k = max(1, round(m / expected_size * @ln2))
    ref = :atomics.new(m, signed: false)
    %__MODULE__{m: m, k: k, ref: ref}
  end

  def add(%__MODULE__{m: m, k: k, ref: ref} = filter, item) do
    Enum.each(0..(k - 1), fn seed ->
      :atomics.put(ref, hash(item, seed, m) + 1, 1)
    end)

    filter
  end

  def member?(%__MODULE__{m: m, k: k, ref: ref}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      :atomics.get(ref, hash(item, seed, m) + 1) == 1
    end)
  end

  def merge(%__MODULE__{m: m, k: k, ref: into} = target, %__MODULE__{m: m, k: k, ref: from}) do
    Enum.each(1..m, fn idx ->
      if :atomics.get(from, idx) == 1 do
        :atomics.put(into, idx, 1)
      end
    end)

    target
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp hash(item, seed, m), do: :erlang.phash2({seed, item}, m)
end
```
