import gleam/erlang/process
import gleamdb
import gleamdb/gleamcms/db/schema as cms_schema
import gleamdb/gleamcms/server/router as cms_router
import gleamdb/gleamcms/builder/importer
import wisp/wisp_mist
import mist
import logging

pub fn main() {
  logging.configure()
  
  // 1. Initialize GleamDB
  let db = gleamdb.new()
  cms_schema.init_schema(db)
  
  // 2. Perform Legacy Import (Demo)
  let _ = importer.run_import(db, "legacy_posts.json")
  
  // 3. Secret Key for Wisp
  let secret_key_base = "fake_secret_key_base_for_local_dev"
  
  // 4. Start Wisp Server
  let assert Ok(_) = 
    wisp_mist.handler(cms_router.handle_request(_, db), secret_key_base)
    |> mist.new()
    |> mist.port(4000)
    |> mist.start()

  process.sleep_forever()
}
