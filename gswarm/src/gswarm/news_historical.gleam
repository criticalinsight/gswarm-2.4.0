import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result
import gleam/list
import gleam/io
import gleam/int
import gleam/string
import gleam/dynamic/decode
import gleamdb
import gleamdb/fact

const news_api_url = "https://min-api.cryptocompare.com/data/v2/news/?lang=EN"

pub type NewsItem {
  NewsItem(
    id: String,
    title: String,
    body: String,
    url: String,
    published_on: Int
  )
}

pub fn ingest_historical_news(db: gleamdb.Db, before_ts: Int, count: Int) {
  io.println("📰 News Oracle: Fetching " <> int.to_string(count) <> " news items before " <> int.to_string(before_ts))
  case fetch_historical_news(before_ts) {
    Ok(items) -> {
      let items_to_ingest = list.take(items, count)
      list.each(items_to_ingest, fn(item) {
        ingest_news_item(db, item)
      })
      io.println("📰 News Oracle: Successfully ingested " <> int.to_string(list.length(items_to_ingest)) <> " historical items.")
    }
    Error(e) -> io.println("⚠️ News Oracle Error: " <> e)
  }
}

fn fetch_historical_news(l_ts: Int) -> Result(List(NewsItem), String) {
  let url = news_api_url <> "&lTs=" <> int.to_string(l_ts)
  let req = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req)
  
  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> decode_news(resp.body)
    _ -> Error("HTTP Error")
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

fn ingest_news_item(db: gleamdb.Db, item: NewsItem) {
  let vec = text_to_vector(item.title)
  let facts = [
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/id", fact.Str(item.id)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/title", fact.Str(item.title)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/vector", fact.Vec(vec)),
    #(fact.Lookup(#("news/id", fact.Str(item.id))), "news/timestamp", fact.Int(item.published_on))
  ]
  let _ = gleamdb.transact(db, facts)
}

fn text_to_vector(text: String) -> List(Float) {
  let hash = string.length(text)
  [
    int.to_float(hash % 100) /. 100.0,
    int.to_float(hash % 50) /. 50.0,
    int.to_float(hash % 10) /. 10.0
  ]
}
