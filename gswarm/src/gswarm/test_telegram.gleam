import gleam/io
import gswarm/telegram

pub fn main() {
  let token = case telegram.get_token() {
    Ok(t) -> t
    Error(e) -> {
      io.println("❌ " <> e)
      ""
    }
  }
  
  let chat_id = case telegram.get_chat_id() {
    Ok(c) -> c
    Error(e) -> {
      io.println("❌ " <> e)
      ""
    }
  }
  
  case token != "" && chat_id != "" {
    True -> {
      io.println("🔍 Testing Telegram Connection...")
      case telegram.send_message(token, chat_id, "🤖 *Gswarm Connectivity Test*\nTime: 17:44") {
        Ok(_) -> io.println("✅ Message sent successfully!")
        Error(e) -> io.println("❌ Failed to send message: " <> e)
      }
    }
    False -> Nil
  }
}
