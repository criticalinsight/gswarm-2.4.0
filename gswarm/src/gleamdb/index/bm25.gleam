import gleam/dict.{type Dict}
import gleam/result
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleamdb/fact

pub type BM25Index {
  BM25Index(
    // term -> (entity -> term_frequency)
    term_freq: Dict(String, Dict(fact.EntityId, Int)),
    // term -> document_frequency (count of entities containing term)
    doc_freq: Dict(String, Int),
    // entity -> document_length (total terms in attribute value)
    doc_len: Dict(fact.EntityId, Int),
    // average document length across all entities
    avg_doc_len: Float,
    // total documents (entities with this attribute)
    doc_count: Int,
    // indexed attribute
    attribute: String,
  )
}

pub fn empty(attribute: String) -> BM25Index {
  BM25Index(
    term_freq: dict.new(),
    doc_freq: dict.new(),
    doc_len: dict.new(),
    avg_doc_len: 0.0,
    doc_count: 0,
    attribute: attribute,
  )
}

pub fn build(datoms: List(fact.Datom), attribute: String) -> BM25Index {
  let relevant_datoms = list.filter(datoms, fn(d) { d.attribute == attribute })
  
  let index_acc = list.fold(relevant_datoms, empty(attribute), fn(idx, datom) {
    case datom.value {
      fact.Str(text) -> add(idx, datom.entity, text)
      _ -> idx
    }
  })

  // Finalize average document length
  let total_len = dict.fold(index_acc.doc_len, 0, fn(acc, _, len) { acc + len })
  let count = index_acc.doc_count
  
  let avg_len = case count {
    0 -> 0.0
    _ -> int.to_float(total_len) /. int.to_float(count)
  }

  BM25Index(..index_acc, avg_doc_len: avg_len)
}

pub fn add(index: BM25Index, entity: fact.EntityId, text: String) -> BM25Index {
  let terms = tokenize(text)
  let doc_length = list.length(terms)
  
  // Update term frequencies for this document
  let term_counts = list.fold(terms, dict.new(), fn(acc, term) {
    case dict.get(acc, term) {
      Ok(count) -> dict.insert(acc, term, count + 1)
      Error(_) -> dict.insert(acc, term, 1)
    }
  })

  // Update global term frequencies and document frequencies
  let #(new_tf, new_df) = dict.fold(term_counts, #(index.term_freq, index.doc_freq), fn(acc, term, count) {
    let #(tf_acc, df_acc) = acc
    
    // Update term frequency map: term -> entity -> count
    let term_entry = case dict.get(tf_acc, term) {
      Ok(entry) -> dict.insert(entry, entity, count)
      Error(_) -> dict.from_list([#(entity, count)])
    }
    let new_tf_acc = dict.insert(tf_acc, term, term_entry)
    
    // Update document frequency: increment if this is a new document for this term
    let new_df_acc = case dict.get(df_acc, term) {
       Ok(df) -> {
          // Verify if we already counted this doc? Attempting strict update logic.
          // Since we are adding a 'new' document or 'new version', we assume it wasn't there or was removed.
          // If we add same doc twice without remove, DF is wrong.
          // Correct usage: Retract then Assert.
          dict.insert(df_acc, term, df + 1)
       }
       Error(_) -> dict.insert(df_acc, term, 1)
    }
    
    #(new_tf_acc, new_df_acc)
  })

  // Incremental avg_doc_len update
  let old_total_len = index.avg_doc_len *. int.to_float(index.doc_count)
  let new_count = index.doc_count + 1
  let new_avg_len = {old_total_len +. int.to_float(doc_length)} /. int.to_float(new_count)

  BM25Index(
    term_freq: new_tf,
    doc_freq: new_df,
    doc_len: dict.insert(index.doc_len, entity, doc_length),
    avg_doc_len: new_avg_len,
    doc_count: new_count,
    attribute: index.attribute,
  )
}

pub fn remove(index: BM25Index, entity: fact.EntityId, text: String) -> BM25Index {
  let terms = tokenize(text)
  let doc_length = list.length(terms)
  
  // Calculate term counts to know what to decrement
  let term_counts = list.fold(terms, dict.new(), fn(acc, term) {
    case dict.get(acc, term) {
      Ok(count) -> dict.insert(acc, term, count + 1)
      Error(_) -> dict.insert(acc, term, 1)
    }
  })

  let #(new_tf, new_df) = dict.fold(term_counts, #(index.term_freq, index.doc_freq), fn(acc, term, _count) {
     let #(tf_acc, df_acc) = acc
     
     // Remove entity from term's frequency map
     let new_tf_acc = case dict.get(tf_acc, term) {
       Ok(entry) -> {
         let new_entry = dict.delete(entry, entity)
         case dict.size(new_entry) {
           0 -> dict.delete(tf_acc, term)
           _ -> dict.insert(tf_acc, term, new_entry)
         }
       }
       Error(_) -> tf_acc
     }
     
     // Decrement document frequency
     let new_df_acc = case dict.get(df_acc, term) {
       Ok(df) if df > 1 -> dict.insert(df_acc, term, df - 1)
       Ok(_) -> dict.delete(df_acc, term)
       Error(_) -> df_acc
     }
     
     #(new_tf_acc, new_df_acc)
  })
  
  // Update avg_doc_len
  let old_total_len = index.avg_doc_len *. int.to_float(index.doc_count)
  let new_count = int.max(0, index.doc_count - 1)
  let new_avg_len = case new_count {
    0 -> 0.0
    _ -> {old_total_len -. int.to_float(doc_length)} /. int.to_float(new_count)
  }

  BM25Index(
    term_freq: new_tf,
    doc_freq: new_df,
    doc_len: dict.delete(index.doc_len, entity),
    avg_doc_len: new_avg_len,
    doc_count: new_count,
    attribute: index.attribute,
  )
}

pub fn score(
  index: BM25Index,
  entity: fact.EntityId,
  query: String,
  k1: Float,
  b: Float,
) -> Float {
  let terms = tokenize(query)
  
  list.fold(terms, 0.0, fn(acc, term) {
    let tf = get_term_freq(index, entity, term)
    let df = get_doc_freq(index, term)
    let doc_len = get_doc_len(index, entity)
    
    // IDF = log(1.0 + (N - df + 0.5) / (df + 0.5))
    // Uses standard BM25 IDF formula
    let idf_numerator = int.to_float(index.doc_count) -. int.to_float(df) +. 0.5
    let idf_denominator = int.to_float(df) +. 0.5
    // Ensure positive IDF (can be negative for very common terms in standard formula)
    let idf = float.logarithm(1.0 +. idf_numerator /. idf_denominator) |> result.unwrap(0.0)
    let safe_idf = float.max(0.0, idf)

    // BM25 = IDF * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (|D| / avgdl)))
    let tf_float = int.to_float(tf)
    let numerator = tf_float *. {k1 +. 1.0}
    
    let avg_dl_safe = case index.avg_doc_len {
      0.0 -> 1.0
      val -> val
    }
    
    let denominator = tf_float +. k1 *. {
      1.0 -. b +. b *. {int.to_float(doc_len) /. avg_dl_safe}
    }
    
    case denominator {
      0.0 -> acc
      _ -> acc +. safe_idf *. {numerator /. denominator}
    }
  })
}

fn tokenize(text: String) -> List(String) {
  text
  |> string.lowercase()
  // Basic tokenization: split on non-alphanumeric chars
  // In a real implementation, would use regex or proper tokenizer
  |> string.to_graphemes()
  |> list.map(fn(char) {
    case is_alphanumeric(char) {
      True -> char
      False -> " "
    }
  })
  |> string.concat()
  |> string.split(" ")
  |> list.filter(fn(s) { string.length(s) > 0 })
}

fn is_alphanumeric(char: String) -> Bool {
  let code = case string.to_utf_codepoints(char) {
    [cp] -> string.utf_codepoint_to_int(cp)
    _ -> 0
  }
  // 0-9, A-Z, a-z
  {code >= 48 && code <= 57} || {code >= 65 && code <= 90} || {code >= 97 && code <= 122}
}

fn get_term_freq(index: BM25Index, entity: fact.EntityId, term: String) -> Int {
  case dict.get(index.term_freq, term) {
    Ok(entity_map) -> case dict.get(entity_map, entity) {
      Ok(count) -> count
      Error(_) -> 0
    }
    Error(_) -> 0
  }
}

fn get_doc_freq(index: BM25Index, term: String) -> Int {
  case dict.get(index.doc_freq, term) {
    Ok(count) -> count
    Error(_) -> 0
  }
}

fn get_doc_len(index: BM25Index, entity: fact.EntityId) -> Int {
  case dict.get(index.doc_len, entity) {
    Ok(len) -> len
    Error(_) -> 0
  }
}
