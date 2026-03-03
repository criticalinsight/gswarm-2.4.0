import gleam/bit_array
import gleam/result
import gleamdb/shared/types.{type Rule}

@external(erlang, "erlang", "term_to_binary")
fn term_to_binary(term: a) -> BitArray

@external(erlang, "erlang", "binary_to_term")
fn binary_to_term(binary: BitArray) -> a

pub fn serialize(rule: Rule) -> String {
  let bits = term_to_binary(rule)
  bit_array.base64_encode(bits, False)
}

pub fn deserialize(s: String) -> Result(Rule, Nil) {
  use bits <- result.try(bit_array.base64_decode(s))
  // Unsafe cast via dynamic might be better, but for internal storage it's acceptable "Rich Hickey" pragmatism
  // essentially "we stored it, we know what it is".
  // However, binary_to_term crashes if invalid? No, it usually returns the term.
  // We need to trust the stored data is a Rule.
  Ok(binary_to_term(bits))
}
