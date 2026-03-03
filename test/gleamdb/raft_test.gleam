import gleeunit/should
import gleam/list
import gleam/option.{None, Some}
import gleamdb/raft

// Helper: create a fake Pid for testing.
// In BEAM, we can use process.self() but for pure state machine tests
// we use the actual process self.
import gleamdb/process_extra

// --- Election Timeout Tests ---

pub fn follower_becomes_candidate_on_timeout_test() {
  let self_pid = process_extra.self()
  let state = raft.new([])

  let #(new_state, effects) = raft.handle_message(state, raft.ElectionTimeout, self_pid)
  
  // Single-node cluster: immediately becomes Leader (has majority with 1 vote)
  should.equal(new_state.role, raft.Leader)
  should.equal(new_state.current_term, 1)
  should.equal(new_state.voted_for, Some(self_pid))
  should.equal(new_state.votes_received, 1)
  
  // Should emit RegisterAsLeader and StartHeartbeatTimer
  let has_register = list.any(effects, fn(e) {
    case e { raft.RegisterAsLeader -> True _ -> False }
  })
  should.be_true(has_register)
}

pub fn candidate_increments_term_on_timeout_test() {
  let self_pid = process_extra.self()
  let peer1 = self_pid  // Using self as fake peer for simplicity
  let state = raft.RaftState(
    role: raft.Candidate,
    current_term: 3,
    voted_for: Some(self_pid),
    peers: [peer1],
    votes_received: 1,
    leader_pid: None,
  )
  
  let #(new_state, _effects) = raft.handle_message(state, raft.ElectionTimeout, self_pid)
  
  // Term should increment
  should.equal(new_state.current_term, 4)
  should.equal(new_state.voted_for, Some(self_pid))
}

pub fn leader_ignores_election_timeout_test() {
  let self_pid = process_extra.self()
  let state = raft.RaftState(
    role: raft.Leader,
    current_term: 5,
    voted_for: Some(self_pid),
    peers: [],
    votes_received: 1,
    leader_pid: Some(self_pid),
  )
  
  let #(new_state, effects) = raft.handle_message(state, raft.ElectionTimeout, self_pid)
  
  // Leader should not change
  should.equal(new_state.role, raft.Leader)
  should.equal(new_state.current_term, 5)
  should.equal(list.length(effects), 0)
}

// --- Vote Request Tests ---

pub fn follower_grants_vote_for_higher_term_test() {
  let self_pid = process_extra.self()
  let candidate_pid = self_pid  // Using self as stand-in
  let state = raft.new([])
  
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.VoteRequest(term: 1, candidate: candidate_pid),
    self_pid,
  )
  
  should.equal(new_state.role, raft.Follower)
  should.equal(new_state.current_term, 1)
  should.equal(new_state.voted_for, Some(candidate_pid))
  
  // Should send a granted VoteResponse
  let has_granted = list.any(effects, fn(e) {
    case e { raft.SendVoteResponse(_, _, True) -> True _ -> False }
  })
  should.be_true(has_granted)
}

pub fn follower_rejects_vote_for_stale_term_test() {
  let self_pid = process_extra.self()
  let candidate_pid = self_pid
  let state = raft.RaftState(
    ..raft.new([]),
    current_term: 5,
  )
  
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.VoteRequest(term: 3, candidate: candidate_pid),
    self_pid,
  )
  
  // Should not change term or vote
  should.equal(new_state.current_term, 5)
  
  // Should send a rejected VoteResponse
  let has_rejected = list.any(effects, fn(e) {
    case e { raft.SendVoteResponse(_, _, False) -> True _ -> False }
  })
  should.be_true(has_rejected)
}

// --- Heartbeat Tests ---

pub fn follower_resets_on_valid_heartbeat_test() {
  let self_pid = process_extra.self()
  let leader_pid = self_pid
  let state = raft.RaftState(
    ..raft.new([]),
    current_term: 1,
  )
  
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.Heartbeat(term: 2, leader: leader_pid),
    self_pid,
  )
  
  should.equal(new_state.role, raft.Follower)
  should.equal(new_state.current_term, 2)
  should.equal(new_state.leader_pid, Some(leader_pid))
  
  // Should reset election timer
  let has_reset = list.any(effects, fn(e) {
    case e { raft.ResetElectionTimer -> True _ -> False }
  })
  should.be_true(has_reset)
}

pub fn follower_ignores_stale_heartbeat_test() {
  let self_pid = process_extra.self()
  let leader_pid = self_pid
  let state = raft.RaftState(
    ..raft.new([]),
    current_term: 5,
  )
  
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.Heartbeat(term: 3, leader: leader_pid),
    self_pid,
  )
  
  // Should not change term
  should.equal(new_state.current_term, 5)
  should.equal(list.length(effects), 0)
}

// --- Term Monotonicity ---

pub fn leader_steps_down_on_higher_term_heartbeat_test() {
  let self_pid = process_extra.self()
  let new_leader = self_pid
  let state = raft.RaftState(
    role: raft.Leader,
    current_term: 3,
    voted_for: Some(self_pid),
    peers: [],
    votes_received: 1,
    leader_pid: Some(self_pid),
  )
  
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.Heartbeat(term: 5, leader: new_leader),
    self_pid,
  )
  
  // Should step down to Follower
  should.equal(new_state.role, raft.Follower)
  should.equal(new_state.current_term, 5)
  
  // Should unregister as leader and stop heartbeat timer
  let has_unregister = list.any(effects, fn(e) {
    case e { raft.UnregisterAsLeader -> True _ -> False }
  })
  should.be_true(has_unregister)
  
  let has_stop = list.any(effects, fn(e) {
    case e { raft.StopHeartbeatTimer -> True _ -> False }
  })
  should.be_true(has_stop)
}

// --- Vote Response / Majority ---

pub fn candidate_becomes_leader_on_majority_test() {
  let self_pid = process_extra.self()
  let peer1 = self_pid  // Fake peer
  let state = raft.RaftState(
    role: raft.Candidate,
    current_term: 1,
    voted_for: Some(self_pid),
    peers: [peer1],  // 2-node cluster
    votes_received: 1,  // Self-vote
    leader_pid: None,
  )
  
  // Receive a granted vote from peer
  let #(new_state, effects) = raft.handle_message(
    state,
    raft.VoteResponse(term: 1, granted: True, from: peer1),
    self_pid,
  )
  
  // 2/2 votes = majority -> Leader
  should.equal(new_state.role, raft.Leader)
  should.equal(new_state.votes_received, 2)
  
  let has_register = list.any(effects, fn(e) {
    case e { raft.RegisterAsLeader -> True _ -> False }
  })
  should.be_true(has_register)
}

// --- Heartbeat Tick (Leader) ---

pub fn leader_sends_heartbeats_on_tick_test() {
  let self_pid = process_extra.self()
  let peer1 = self_pid
  let state = raft.RaftState(
    role: raft.Leader,
    current_term: 2,
    voted_for: Some(self_pid),
    peers: [peer1],
    votes_received: 2,
    leader_pid: Some(self_pid),
  )
  
  let #(_new_state, effects) = raft.handle_message(
    state,
    raft.HeartbeatTick,
    self_pid,
  )
  
  // Should send heartbeat to each peer
  let heartbeats = list.filter(effects, fn(e) {
    case e { raft.SendHeartbeat(_, _, _) -> True _ -> False }
  })
  should.equal(list.length(heartbeats), 1)
}

pub fn follower_ignores_heartbeat_tick_test() {
  let self_pid = process_extra.self()
  let state = raft.new([])
  
  let #(_new_state, effects) = raft.handle_message(
    state,
    raft.HeartbeatTick,
    self_pid,
  )
  
  should.equal(list.length(effects), 0)
}
