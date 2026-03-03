import gleam/io
import gleam/list
import gleamdb/gleamcms/themes/library
import gleam/string
import gleam/int

pub fn main() {
  let themes = library.get_all()
  let count = list.length(themes)
   io.println("Generated " <> int_to_string(count) <> " themes.")
  
  // Verify first theme (Default Dark)
  let assert Ok(first) = list.first(themes)
  let layout_fn = first.layout
  let html = layout_fn("Test Title", "Test Body")
  
  case string.contains(html, "--bg-color: #0f172a") {
    True -> io.println("SUCCESS: Default Dark theme contains correct bg-color.")
    False -> io.println("FAILURE: Default Dark theme css mismatch.")
  }

  // Verify last theme (Discord)
  let assert Ok(last) = list.last(themes)
  let last_layout_fn = last.layout
  let html_last = last_layout_fn("Test Title", "Test Body")
  
  case string.contains(html_last, "--bg-color: #36393f") {
    True -> io.println("SUCCESS: Discord theme contains correct bg-color.")
    False -> io.println("FAILURE: Discord theme css mismatch.")
  }
}

fn int_to_string(i: Int) -> String {
  int.to_string(i)
}
