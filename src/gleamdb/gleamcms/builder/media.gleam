import gleam/io
import simplifile
import gleam/crypto
import gleam/bit_array

pub type AssetHash = String

pub fn store_asset(content: BitArray, extension: String) -> Result(AssetHash, String) {
  // 1. Compute SHA-256 hash of the content (CAS)
  let hash = crypto.hash(crypto.Sha256, content)
    |> bit_array.base16_encode()

  let filename = hash <> "." <> extension
  let path = "priv/static/media/" <> filename

  // 2. Deduplication check: If file exists, we are done
  case simplifile.is_file(path) {
    Ok(True) -> {
      io.println("Asset exists (deduplicated): " <> filename)
      Ok(hash)
    }
    _ -> {
      // 3. Write to disk
      case simplifile.write_bits(path, content) {
        Ok(_) -> {
          io.println("Asset stored: " <> filename)
          // 4. Pin to IPFS (Simulated)
          pin_to_ipfs(hash)
          Ok(hash)
        }
        Error(e) -> Error(simplifile.describe_error(e))
      }
    }
  }
}

pub fn get_public_url(hash: AssetHash, extension: String) -> String {
  // Return local path for now, or IPFS gateway
  "/static/media/" <> hash <> "." <> extension
}

fn pin_to_ipfs(hash: String) {
  // In a real implementation, this would make an HTTP request to a pinning service
  io.println("Pinned to IPFS (Simulated): " <> hash)
}

