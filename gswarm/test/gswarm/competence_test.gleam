import gleeunit
import gleeunit/should
import gswarm/competence

pub fn main() {
  gleeunit.main()
}

pub fn brier_score_test() {
  // Perfect prediction (YES)
  competence.calculate_brier_score(1.0, 1.0) |> should.equal(0.0)
  
  // Perfect prediction (NO)
  competence.calculate_brier_score(0.0, 0.0) |> should.equal(0.0)
  
  // Total fail
  competence.calculate_brier_score(1.0, 0.0) |> should.equal(1.0)
  
  // Half right (0.5 prob vs 1.0 outcome)
  // (0.5 - 1.0)^2 = 0.25
  competence.calculate_brier_score(0.5, 1.0) |> should.equal(0.25)
}

pub fn competence_index_test() {
  // Scenario 1: High Alpha, Perfect Calibration, 4 trades
  // Alpha=0.8, Brier=0.0 (Calibration=1.0), N=4 (sqrt=2.0)
  // 0.8 * 1.0 * 2.0 = 1.6
  competence.calculate_competence_index(0.8, 0.0, 4) |> should.equal(1.6)
  
  // Scenario 2: High Alpha, Poor Calibration, 4 trades
  // Alpha=0.8, Brier=0.5 (Calibration=0.5), N=4 (sqrt=2.0)
  // 0.8 * 0.5 * 2.0 = 0.8
  competence.calculate_competence_index(0.8, 0.5, 4) |> should.equal(0.8)
  
  // Scenario 3: Low Alpha, Perfect Calibration, 100 trades
  // Alpha=0.1, Brier=0.0 (Calibration=1.0), N=100 (sqrt=10.0)
  // 0.1 * 1.0 * 10.0 = 1.0
  competence.calculate_competence_index(0.1, 0.0, 100) |> should.equal(1.0)
}
