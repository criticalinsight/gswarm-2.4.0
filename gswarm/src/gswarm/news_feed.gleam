import gleam/io
import gleam/int
import gleam/string
import gleam/list
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/dynamic/decode
import gleam/result
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{type DbState}
import gswarm/sentiment

// Using CryptoCompare News API (Public)
const news_api_url = "https://min-api.cryptocompare.com/data/v2/news/?lang=EN"

pub fn start_news_feed(db: gleamdb.Db) {
  process.spawn_unlinked(fn() {
    loop(db)
  })
}

fn loop(db: gleamdb.Db) {
  case fetch_news() {
    Ok(news_items) -> {
      let _ = list.each(news_items, fn(item) {
        ingest_news(db, item)
      })
      io.println("📰 News Feed: Ingested " <> int.to_string(list.length(news_items)) <> " headlines.")
    }
    Error(e) -> io.println("⚠️ News Feed Error: " <> e)
  }
  
  process.sleep(60000) // Poll every 60s
  loop(db)
}

pub type NewsItem {
  NewsItem(
    id: String,
    title: String,
    body: String,
    url: String,
    published_on: Int
  )
}

fn fetch_news() -> Result(List(NewsItem), String) {
  let req_result = request.to(news_api_url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)
  
  use resp <- result.try(httpc.send(req) |> result.map_error(fn(_e) { "HTTP Error" }))
  
  case resp.status {
    200 -> decode_news(resp.body)
    _ -> Error("API returned status " <> int.to_string(resp.status))
  }
}

fn decode_news(json_str: String) -> Result(List(NewsItem), String) {
  let decoder = {
    use data <- decode.field("Data", decode.list({
      use id <- decode.field("id", decode.string)
      use title <- decode.field("title", decode.string)
      use body <- decode.field("body", decode.string)
      use url <- decode.field("url", decode.string)
      use published_on <- decode.field("published_on", decode.int)
      decode.success(NewsItem(id, title, body, url, published_on))
    }))
    decode.success(data)
  }
  
  json.parse(from: json_str, using: decoder)
  |> result.map_error(fn(_) { "JSON Decode Failed" })
}

fn text_to_vector(text: String) -> List(Float) {
  // "Semantic Hashing" + Sentiment Grounding (Phase 49)
  let sentiment_score = sentiment.score(text)
  let hash = string.length(text)
  
  [
    sentiment_score, // Dimension 0: Sentiment (-1.0 to 1.0)
    int.to_float(hash % 100) /. 100.0,
    int.to_float(hash % 50) /. 50.0
  ]
}

fn ingest_news(db: gleamdb.Db, item: NewsItem) -> Result(DbState, String) {
  // Vectorize Title
  let vec = text_to_vector(item.title)
  
  let facts = [
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/title", fact.Str(item.title)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/url", fact.Str(item.url)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/vector", fact.Vec(vec)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/sentiment", fact.Float(sentiment.score(item.title))),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/timestamp", fact.Int(item.published_on))
  ]
  
  gleamdb.transact(db, facts)
}
