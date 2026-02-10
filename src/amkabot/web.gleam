import amkabot/domain
import amkabot/stats
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import pog
import wisp.{type Request, type Response}

pub type Context {
  Context(stats_aggregator: Subject(stats.Message), db: pog.Connection)
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes

  case wisp.path_segments(req) {
    [] -> home_page()
    ["leaderboard"] -> leaderboard_page(ctx)
    ["trader", address] -> trader_detail_page(ctx, address)
    ["api", "trader", address, "history"] -> trader_history_api(ctx, address)
    _ -> wisp.not_found()
  }
}

fn home_page() -> Response {
  let html =
    "
    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <title>Amkabot - Prediction Market Tracker</title>
        <style>
            body { font-family: 'Inter', system-ui, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
            .card { background: #1e293b; padding: 3rem; border-radius: 1rem; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5); text-align: center; border: 1px solid #334155; }
            h1 { font-size: 2.5rem; margin-bottom: 1rem; background: linear-gradient(to right, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
            p { color: #94a3b8; font-size: 1.1rem; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 0.75rem 1.5rem; border-radius: 0.5rem; text-decoration: none; font-weight: 600; transition: all 0.2s; margin-top: 1.5rem; }
            .btn:hover { background: #2563eb; transform: translateY(-2px); }
        </style>
    </head>
    <body>
        <div class=\"card\">
            <h1>Amkabot 📡</h1>
            <p>High-fidelity Prediction Market Analytics Engine</p>
            <a href=\"/leaderboard\" class=\"btn\">Enter Leaderboard</a>
        </div>
    </body>
    </html>
  "
  wisp.ok()
  |> wisp.html_body(html)
}

fn leaderboard_page(ctx: Context) -> Response {
  let reply = process.new_subject()
  process.send(ctx.stats_aggregator, stats.GetAllStats(reply))

  let trader_stats: List(stats.Stats) =
    process.receive(reply, 2000)
    |> result.unwrap([])
    |> list.sort(fn(a: stats.Stats, b: stats.Stats) {
      float.compare(b.total_pnl, a.total_pnl)
    })

  let rows =
    list.map(trader_stats, fn(s: stats.Stats) {
      let pnl_color = case s.total_pnl >=. 0.0 {
        True -> "#10b981"
        _ -> "#ef4444"
      }

      let calibration = case s.prediction_count > 0 {
        True -> s.calibration_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }

      let formatted_pnl =
        { s.total_pnl *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_roi =
        { s.roi *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_calib =
        { calibration *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string

      "<tr id=\"trader-" <> s.trader_id <> "\">
      <td style=\"font-family: monospace; color: #94a3b8;\"><a href=\"/trader/" <> s.trader_id <> "\" style=\"color: inherit; text-decoration: none;\">" <> s.trader_id <> "</a></td>
      <td class=\"pnl\" style=\"color: " <> pnl_color <> "; font-weight: bold;\">$" <> formatted_pnl <> "</td>
      <td class=\"roi\">" <> formatted_roi <> "%</td>
      <td class=\"calib\">" <> formatted_calib <> "</td>
      <td class=\"preds\">" <> int.to_string(s.prediction_count) <> "</td>
    </tr>"
    })
    |> list.fold("", fn(acc, row) { acc <> row })

  let html = "
    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <title>Trader Leaderboard | Amkabot</title>
        <style>
            body { font-family: 'Inter', system-ui, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; }
            .container { max-width: 1000px; margin: 0 auto; }
            h1 { font-size: 2rem; margin-bottom: 2rem; border-left: 4px solid #3b82f6; padding-left: 1rem; }
            table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 0.75rem; overflow: hidden; border: 1px solid #334155; }
            th { text-align: left; padding: 1rem; background: #334155; color: #94a3b8; font-size: 0.875rem; text-transform: uppercase; letter-spacing: 0.05em; }
            td { padding: 1rem; border-bottom: 1px solid #334155; }
            tr:last-child td { border-bottom: none; }
            a:hover { text-decoration: underline !important; }
            .back-link { display: inline-block; margin-top: 1.5rem; color: #64748b; text-decoration: none; font-size: 0.875rem; }
            .back-link:hover { color: #94a3b8; }
            .flash { animation: flash_green 1s; }
            @keyframes flash_green { 0% { background: #064e3b; } 100% { background: transparent; } }
        </style>
    </head>
    <body>
        <div class=\"container\">
            <h1>Market Master Leaderboard <span id=\"status\" style=\"font-size: 0.8rem; color: #10b981;\">● Live</span></h1>
            <table>
                <thead>
                    <tr>
                        <th>Trader Address</th>
                        <th>Realized PnL</th>
                        <th>ROI (Est.)</th>
                        <th>Calibration</th>
                        <th>Resolved Preds</th>
                    </tr>
                </thead>
                <tbody id=\"leaderboard-body\">
                    " <> rows <> "
                </tbody>
            </table>
            <a href=\"/\" class=\"back-link\">← Back to Analytics Overview</a>
        </div>
        <script>
            const socket = new WebSocket('ws://' + window.location.host + '/ws');
            socket.onmessage = (event) => {
                const data = JSON.parse(event.data);
                const row = document.getElementById('trader-' + data.trader_id);
                if (row) {
                    row.querySelector('.pnl').innerText = '$' + data.total_pnl.toFixed(2);
                    row.querySelector('.pnl').style.color = data.total_pnl >= 0 ? '#10b981' : '#ef4444';
                    row.querySelector('.roi').innerText = data.roi.toFixed(2) + '%';
                    row.querySelector('.preds').innerText = data.preds;
                    row.querySelector('.calib').innerText = data.calib.toFixed(2);
                    row.classList.add('flash');
                    setTimeout(() => row.classList.remove('flash'), 1000);
                } else {
                    window.location.reload();
                }
            };
            socket.onclose = () => {
                document.getElementById('status').style.color = '#ef4444';
                document.getElementById('status').innerText = '● Disconnected';
            };
        </script>
    </body>
    </html>
  "

  wisp.ok()
  |> wisp.html_body(html)
}

fn trader_detail_page(ctx: Context, address: String) -> Response {
  let reply = process.new_subject()
  process.send(ctx.stats_aggregator, stats.GetStats(address, reply))

  let stats_result =
    process.receive(reply, 2000)
    |> result.flatten

  case stats_result {
    Ok(s) -> {
      let pnl_color = case s.total_pnl >=. 0.0 {
        True -> "#10b981"
        _ -> "#ef4444"
      }
      let calib_score = case s.prediction_count > 0 {
        True -> s.calibration_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }
      let sharp_score = case s.prediction_count > 0 {
        True -> s.sharpness_sum /. int.to_float(s.prediction_count)
        False -> 0.0
      }
      let formatted_pnl =
        { s.total_pnl *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_roi =
        { s.roi *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_calib =
        { calib_score *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string
      let formatted_sharp =
        { sharp_score *. 100.0 |> float.round |> int.to_float } /. 100.0
        |> float.to_string

      // Fetch historical data from Actor (Snapshots + Activity)
      let reply_hist = process.new_subject()
      process.send(ctx.stats_aggregator, stats.GetHistory(address, reply_hist))
      let #(history_snaps, history_activities) =
        process.receive(reply_hist, 2000)
        |> result.unwrap(Ok(#([], [])))
        |> result.unwrap(#([], []))

      let history_rows = render_activity_rows(history_activities)
      let sparkline_svg = generate_sparkline(history_snaps)

      let html = "
            <!DOCTYPE html>
            <html lang=\"en\">
            <head>
                <meta charset=\"UTF-8\">
                <title>Trader Detail | Amkabot</title>
                <style>
                    body { font-family: 'Inter', system-ui, sans-serif; background: #0f172a; color: #f8fafc; padding: 4rem; }
                    .container { max-width: 850px; margin: 0 auto; background: #1e293b; padding: 3rem; border-radius: 1rem; border: 1px solid #334155; }
                    h1 { font-size: 1.2rem; color: #94a3b8; margin-bottom: 0.5rem; font-family: monospace; overflow-wrap: break-word; }
                    .value { font-size: 3rem; font-weight: 800; margin-bottom: 2rem; color: " <> pnl_color <> "; }
                    .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 2rem; border-top: 1px solid #334155; padding-top: 2rem; margin-bottom: 3rem; }
                    .label { color: #64748b; font-size: 0.875rem; text-transform: uppercase; margin-bottom: 0.5rem; }
                    .stat { font-size: 1.5rem; font-weight: 600; }
                    .history-title { font-size: 1.25rem; font-weight: bold; margin-bottom: 1rem; border-bottom: 1px solid #334155; padding-bottom: 0.5rem; display: flex; justify-content: space-between; align-items: center; }
                    .history-item { display: flex; justify-content: space-between; padding: 0.75rem 0; border-bottom: 1px solid #1e293b; color: #cbd5e1; font-size: 0.95rem; }
                    .history-item:last-child { border-bottom: none; }
                    .type-badge { padding: 0.25rem 0.5rem; border-radius: 0.25rem; font-size: 0.75rem; font-weight: bold; text-transform: uppercase; }
                    .BUY { background: #3b82f6; color: white; }
                    .SELL { background: #f59e0b; color: white; }
                    .REDEEM { background: #10b981; color: white; }
                    .back { display: block; margin-top: 3rem; color: #3b82f6; text-decoration: none; font-weight: 500; }
                    .sparkline-container { margin-bottom: 2rem; padding: 1rem; background: #0f172a; border-radius: 0.5rem; }
                </style>
            </head>
            <body>
                <div class=\"container\">
                    <h1>Trader: " <> s.trader_id <> "</h1>
                    <div class=\"value\">$" <> formatted_pnl <> " <span style=\"font-size: 1rem; font-weight: normal; color: #64748b;\">Realized PnL</span></div>
                    
                    <div class=\"grid\">
                        <div>
                            <div class=\"label\">ROI (Est.)</div>
                            <div class=\"stat\">" <> formatted_roi <> "%</div>
                        </div>
                        <div>
                            <div class=\"label\">Calibration Score</div>
                            <div class=\"stat\">" <> formatted_calib <> "</div>
                        </div>
                        <div>
                            <div class=\"label\">Sharpness Score</div>
                            <div class=\"stat\">" <> formatted_sharp <> "</div>
                        </div>
                        <div>
                            <div class=\"label\">Resolved Predictions</div>
                            <div class=\"stat\">" <> int.to_string(
          s.prediction_count,
        ) <> "</div>
                        </div>
                    </div>

                    <div class=\"sparkline-container\">
                        <div class=\"label\">Calibration Trend (90 Days)</div>
                        " <> sparkline_svg <> "
                    </div>

                    <div class=\"history\">
                        <div class=\"history-title\">
                            Historical Activity Feed
                            <a href=\"/api/trader/" <> address <> "/history\" style=\"font-size: 0.8rem; color: #3b82f6; text-decoration: none;\">JSON API</a>
                        </div>
                        " <> history_rows <> "
                    </div>
                    
                    <a href=\"/leaderboard\" class=\"back\">← Back to Leaderboard</a>
                </div>
            </body>
            </html>
        "
      wisp.ok() |> wisp.html_body(html)
    }
    Error(_) -> wisp.not_found()
  }
}

fn trader_history_api(ctx: Context, address: String) -> Response {
  let reply = process.new_subject()
  process.send(ctx.stats_aggregator, stats.GetHistory(address, reply))

  let result = process.receive(reply, 2000)
  case result {
    Ok(Ok(#(history, _))) -> {
      let json_data =
        json.object([
          #("address", json.string(address)),
          #(
            "history",
            json.preprocessed_array(
              list.map(history, fn(h) {
                json.object([
                  #("date", json.string(h.date)),
                  #("calibration", json.float(h.calibration_score)),
                  #("sharpness", json.float(h.sharpness_score)),
                ])
              }),
            ),
          ),
        ])
      wisp.json_response(json.to_string(json_data), 200)
    }
    _ -> wisp.internal_server_error()
  }
}

fn render_activity_rows(activities: List(domain.TradeActivity)) -> String {
  case list.length(activities) {
    0 -> "<div style=\"color: #64748b; font-style: italic; padding: 1rem;\">No recent activity recorded.</div>"
    _ -> {
      list.map(activities, fn(a) {
        let type_badge = string.uppercase(string.inspect(a.trade_type))
        "<div class=\"history-item\">
            <span><span class=\"type-badge " <> type_badge <> "\">" <> type_badge <> "</span> " <> a.market_slug <> "</span>
            <span style=\"color: #94a3b8;\">$" <> float.to_string(a.usdc_size) <> " @ " <> float.to_string(a.price) <> "</span>
        </div>"
      })
      |> string.join("")
    }
  }
}



// Minimalist server-side SVG sparkline generator
fn generate_sparkline(data: List(stats.TraderSnapshot)) -> String {
  case list.length(data) {
    0 ->
      "<div style=\"color: #64748b; font-style: italic; padding: 1rem;\">Not enough history for trend analysis.</div>"
    _ -> {
      let width = 800.0
      let height = 100.0
      let count = list.length(data)
      let step_x = width /. int.to_float(int.max(1, count - 1))

      let points =
        list.index_map(data, fn(d, i) {
          let x = int.to_float(i) *. step_x
          // Y-axis: Calibration 0.0 is best (top), 1.0 is worst (bottom)
          // We invert for chart: 0.0 -> height, 1.0 -> 0
          // Wait, calibration_score in code: 1.0 - error. So 1.0 is best.
          // So 1.0 -> 0 (top), 0.0 -> height (bottom)
          let y = height -. { d.calibration_score *. height }
          float.to_string(x) <> "," <> float.to_string(y)
        })
        |> string.join(" ")

      "<svg width=\"100%\" height=\"100\" viewBox=\"0 0 800 100\" preserveAspectRatio=\"none\">
         <defs>
           <linearGradient id=\"grad\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">
             <stop offset=\"0%\" style=\"stop-color:#3b82f6;stop-opacity:1\" />
             <stop offset=\"100%\" style=\"stop-color:#3b82f6;stop-opacity:0.1\" />
           </linearGradient>
         </defs>
         <path d=\"M0,100 L"
      <> points
      <> " L800,100 Z\" fill=\"url(#grad)\" stroke=\"none\" />
         <polyline points=\""
      <> points
      <> "\" fill=\"none\" stroke=\"#60a5fa\" stroke-width=\"2\" />
       </svg>"
    }
  }
}
