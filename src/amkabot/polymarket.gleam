import amkabot/domain.{
  type Market, type TradeActivity, Buy, Market, Open, Redeem, Sell,
  TradeActivity,
}
import gleam/dynamic/decode
import gleam/hackney
import gleam/http/request
import gleam/int
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string

const gamma_url = "https://gamma-api.polymarket.com"

const data_url = "https://data-api.polymarket.com/v1"

pub type APIError {
  NetworkError(String)
  ParseError(String)
}

fn decode_number_as_float() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub fn fetch_markets() -> Result(List(Market), APIError) {
  let url = gamma_url <> "/markets?active=true&limit=20"
  let req_result =
    request.to(url) |> result.map_error(fn(_) { NetworkError("Invalid URL") })
  use req <- result.try(req_result)
  let res_result =
    hackney.send(req)
    |> result.map_error(fn(e) { NetworkError(string.inspect(e)) })
  use res <- result.try(res_result)
  case res.status {
    200 -> decode_markets(res.body)
    _ -> Error(NetworkError("API returned " <> string.inspect(res.status)))
  }
}

pub type LeaderboardEntry {
  LeaderboardEntry(proxy_wallet: String, user_name: String, pnl: Float)
}

pub fn fetch_leaderboard() -> Result(List(LeaderboardEntry), APIError) {
  let url = data_url <> "/leaderboard?orderBy=PNL&limit=5"
  let req_result =
    request.to(url) |> result.map_error(fn(_) { NetworkError("Invalid URL") })
  use req <- result.try(req_result)
  let res_result =
    hackney.send(req)
    |> result.map_error(fn(e) { NetworkError(string.inspect(e)) })
  use res <- result.try(res_result)
  case res.status {
    200 -> decode_leaderboard(res.body)
    _ -> Error(NetworkError("API returned " <> string.inspect(res.status)))
  }
}

pub fn fetch_activity(user: String) -> Result(List(TradeActivity), APIError) {
  let url = data_url <> "/activity?user=" <> user <> "&limit=10"
  let req_result =
    request.to(url) |> result.map_error(fn(_) { NetworkError("Invalid URL") })
  use req <- result.try(req_result)
  let res_result =
    hackney.send(req)
    |> result.map_error(fn(e) { NetworkError(string.inspect(e)) })
  use res <- result.try(res_result)
  case res.status {
    200 -> decode_activity(res.body)
    _ -> Error(NetworkError("API returned " <> string.inspect(res.status)))
  }
}

fn decode_markets(json_string: String) -> Result(List(Market), APIError) {
  let market_decoder = {
    use id <- decode.field("id", decode.string)
    use question <- decode.field("question", decode.string)
    use category <- decode.optional_field(
      "category",
      None,
      decode.optional(decode.string),
    )
    decode.success(Market(
      id: id,
      question: question,
      category: category,
      status: Open,
      outcome: None,
    ))
  }
  json.parse(from: json_string, using: decode.list(market_decoder))
  |> result.map_error(fn(e) { ParseError(string.inspect(e)) })
}

fn decode_leaderboard(
  json_string: String,
) -> Result(List(LeaderboardEntry), APIError) {
  let entry_decoder = {
    use wallet <- decode.field("proxyWallet", decode.string)
    use name <- decode.field("userName", decode.string)
    use pnl <- decode.field("pnl", decode_number_as_float())
    decode.success(LeaderboardEntry(
      proxy_wallet: wallet,
      user_name: name,
      pnl: pnl,
    ))
  }
  json.parse(from: json_string, using: decode.list(entry_decoder))
  |> result.map_error(fn(e) { ParseError(string.inspect(e)) })
}

fn decode_activity(json_string: String) -> Result(List(TradeActivity), APIError) {
  let type_decoder =
    decode.string
    |> decode.then(fn(s) {
      case s {
        "BUY" -> decode.success(Buy)
        "SELL" -> decode.success(Sell)
        "REDEEM" -> decode.success(Redeem)
        _ -> decode.success(Buy)
        // Fallback
      }
    })

  let activity_decoder = {
    use wallet <- decode.field("proxyWallet", decode.string)
    use title <- decode.field("title", decode.string)
    use slug <- decode.field("slug", decode.string)
    use ttype <- decode.field("type", type_decoder)
    use size <- decode.field("size", decode_number_as_float())
    use price <- decode.field("price", decode_number_as_float())
    use usdc <- decode.field("usdcSize", decode_number_as_float())
    use ts <- decode.field("timestamp", decode.int)
    decode.success(TradeActivity(
      user: wallet,
      market_title: title,
      market_slug: slug,
      trade_type: ttype,
      size: size,
      price: price,
      usdc_size: usdc,
      timestamp: ts,
    ))
  }
  json.parse(from: json_string, using: decode.list(activity_decoder))
  |> result.map_error(fn(e) { ParseError(string.inspect(e)) })
}
