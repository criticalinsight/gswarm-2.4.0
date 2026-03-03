import gleam/io
import gleamdb/gleamcms/builder/media

pub fn main() {
  let content = <<"Rich Hickey is my spirit animal":utf8>>
  let extension = "txt"
  
  io.println("--- Test 1: Store Asset ---")
  let assert Ok(hash1) = media.store_asset(content, extension)
  io.println("Hash: " <> hash1)
  
  io.println("\n--- Test 2: Deduplication ---")
  let assert Ok(hash2) = media.store_asset(content, extension)
  
  case hash1 == hash2 {
    True -> io.println("SUCCESS: Hashes match (Deduplicated)")
    False -> io.println("FAILURE: Hashes do not match")
  }
  
  let url = media.get_public_url(hash1, extension)
  io.println("\nPublic URL: " <> url)
}
