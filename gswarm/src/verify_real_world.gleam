import gleam/io
import gleam/string
import gleam/float
import gswarm/ai_brain

pub fn main() {
  io.println("🌍 Gswarm: Verifying Real-World Intelligence (Phase 53)...")
  io.println("---------------------------------------------------------------")

  // 1. Mock "High-Alpha" Trader Data (Simulating Extraction from Live DB)
  // We use a known historical event to verify Search Grounding.
  // Event: Bitcoin ETF Approval (Jan 2024)
  // Trader "0xWhale" buys "YES" early.
  
  let trader_id = "0xWhale_SmartMoney"
  let roi = 145.5
  let win_rate = 0.82
  let total_profit = 54200.0
  
  // Timestamps (approximate)
  // Jan 2, 2024: ~1704153600
  // Jan 10, 2024 (Approval): ~1704844800
  
  let nexus = "Trader: " <> trader_id <> "\n"
    <> "Performance: ROI " <> float.to_string(roi) <> "%, Win Rate " <> float.to_string(win_rate) <> ", Profit $" <> float.to_string(total_profit) <> "\n"
    <> "Recent Activity:\n"
    <> "1. [2024-01-03] BOUGHT 'Bitcoin ETF Approval by Jan 15' at Price $0.45. Size: $15,000.\n"
    <> "   Context: Price spiked to $0.80 on Jan 09. SEC officially approved on Jan 10.\n"
    <> "2. [2024-05-20] BOUGHT 'Ether ETF Approval' at Price $0.15. Size: $10,000.\n"
    <> "   Context: ETF unexpectedly approved on May 23. Price went to $0.90.\n"

  io.println("📋 Generated Trade Nexus for " <> trader_id)
  io.println(nexus)
  io.println("---------------------------------------------------------------")
  io.println("🧠 Sending to AI Brain for Assessment (with Google Search)...")
  
  // 2. Call AI Brain (Real-World Check)
  case ai_brain.assess_trader(nexus) {
    Ok(assessment) -> {
      io.println("✅ AI Assessment Received:")
      io.println("---------------------------------------------------------------")
      io.println(assessment)
      io.println("---------------------------------------------------------------")
      
      // 3. Simple Verification Heuristics
      // We check if the AI mentions key terms indicating it searched and understood.
      let has_rationale = string.contains(does: assessment, contain: "Success Rationale") || string.contains(does: assessment, contain: "Why is this trader winning")
      let has_etf = string.contains(does: assessment, contain: "ETF")
      let has_sec = string.contains(does: assessment, contain: "SEC") || string.contains(does: assessment, contain: "regulatory")
      
      case has_etf && has_sec {
        True -> {
             io.println("✅ Verification PASS: AI identified ETF/Regulatory context.")
             case has_rationale {
               True -> io.println("✅ Verification PASS: AI provided Success Rationale.")
               False -> io.println("⚠️ Verification WARNING: 'Success Rationale' header not found (check prompt compliance).")
             }
        }
        False -> io.println("⚠️ Verification WARNING: AI report might lack specific grounding details (Check output).")
      }
    }
    Error(e) -> {
      io.println("❌ AI Assessment Failed: " <> e)
      io.println("Check GEMINI_API_KEY and internet connection.")
    }
  }
}
