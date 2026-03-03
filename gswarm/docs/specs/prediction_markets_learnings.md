# Learnings: Prediction Markets Integration (Phase 34–38)

> "To predict is to structure time." — Rich Hickey (Paraphrased)

## 1. The Shift to Probability Space
Integrating Manifold Markets forced a fundamental shift in our data model.
- **Crypto**: Infinite, unbounded price (`Float`).
- **Prediction**: Bounded probability (`0.0` to `1.0`).

**Insight**: Normalizing everything to a vector space (`[0, 1]`) makes the *Analyst* agnostic. Whether it's "BTC Price" or "AI Turing Test Probability", the math (Cosine Similarity) remains the same. The `PredictionTick` type enforces this bound at the ingestion edge.

## 2. Entity-per-Tick vs. EAVT Flatness
We initially tried to model ticks as attributes on the Market entity (`tick/price` on `Market`).
- **Problem**: Cartesian product explosions during queries. Querying `tick/price` and `tick/timestamp` caused the Datalog engine to return every combination of price and timestamp (~N²).
- **Solution (Phase 23)**: **Entity-per-Tick**.
    - Every tick is a unique `Entity`.
    - It has a deterministic ID: `hash(market_id, timestamp, outcome)`.
    - It links back to the market: `tick/market -> MarketRef`.

**Result**: Queries become efficient scans over Tick entities, sorted by time. The "Shape" of the data matches the "Shape" of the query.

## 3. Determinisic IDs (Idempotency)
Distributed systems struggle with "exactly-once" delivery.
- **Problem**: If the `LiveTicker` crashes and restarts, it might re-ingest the same tick. With random IDs, we'd get duplicates.
- **Solution**: `phash2` FFI.
    - ID = `hash(MarketID + Timestamp + Outcome)`
    - If we ingest the same tick twice, it maps to the *same* Entity ID.
    - result: **Idempotent Upserts**. The second write just "confirms" the existing fact.

## 4. Vector Sovereignty in Practice
We deployed the **Analyst** to watch `pm_will-ai-pass-the-turing-test`.
- It identified a correlation with `pm_gpt-5-release-date`.
- **Mechanism**: The `latest_vector` attribute.
    - Ingestor writes `tick/vector` (immutable history).
    - Ingestor *also* updates `market/latest_vector` (current context).
    - Analyst queries `market/latest_vector` to find similar markets instantly (O(log n)).

## 5. The "Feedback Loop" Gap
We realized the **Paper Trader** was trading blindly.
- It generated signals but never learned.
- **Fix**: **Result Facts** (`result_fact.gleam`).
    - We now record every prediction.
    - We wait (Resolution or Time Delay).
    - We assert a `Result` fact (Correct/Incorrect).
    - The `StrategySelector` queries these Results to hot-swap logic.

**Conclusion**: The system now *closes the loop*. It is no longer just a feed reader; it is a learning organism.

## 6. Bitemporal and Speculative Learnings (v2.0)
Integrating **Speculative Soul** and **Chronos** solved the "Simulation Credibility" problem.
- **Speculative Trading**: Using `with_facts` allowed the Paper Trader to simulate bets and calculate virtual Brier scores *before* resolution without side effects on persistent storage.
- **Historical Precision**: `as_of_valid` enabled replaying political markets with exact temporal sequence. The v2.0.0 `QueryResult` metadata now provides the explicit `valid_time` and `tx_id` for every result, preventing the "look-ahead" leakage where a poll result from 2pm is used to predict a market move at 1pm.
