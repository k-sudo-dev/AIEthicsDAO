;; AIEthicsDAO - Community governance for AI model ethical compliance
;; Stakeholders vote on standards, auditors evaluate models

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-MODEL-NOT-FOUND (err u101))
(define-constant ERR-AUDITOR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INSUFFICIENT-STAKE (err u104))
(define-constant ERR-AUDIT-COMPLETE (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-DISPUTE-EXISTS (err u107))
(define-constant ERR-CHALLENGE-EXPIRED (err u108))
(define-constant ERR-ALREADY-REPORTED (err u109))
(define-constant ERR-PROPOSAL-EXPIRED (err u110))

(define-data-var standard-count uint u0)
(define-data-var audit-count uint u0)
(define-data-var dispute-count uint u0)
(define-data-var proposal-count uint u0)
(define-data-var min-auditor-stake uint u1000)
(define-data-var governance-threshold uint u10000)
(define-data-var challenge-period uint u144) ;; ~24 hours in blocks
(define-data-var audit-fee-percentage uint u5) ;; 5% platform fee

(define-map ethical-standards
  { standard-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    proposer: principal,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20),
    created-at: uint,
    expires-at: uint
  }
)

(define-map model-audits
  { audit-id: uint }
  {
    model-hash: (buff 32),
    model-name: (string-ascii 100),
    auditor: principal,
    compliance-score: uint,
    issues-found: uint,
    audit-report: (buff 32),
    payment: uint,
    status: (string-ascii 20),
    created-at: uint,
    requester: principal
  }
)

(define-map certified-auditors
  { auditor: principal }
  {
    stake-amount: uint,
    completed-audits: uint,
    reputation-score: uint,
    specializations: (list 5 (string-ascii 50)),
    active: bool,
    slashed-amount: uint
  }
)

(define-map audit-disputes
  { dispute-id: uint }
  {
    audit-id: uint,
    challenger: principal,
    reason: (string-ascii 200),
    stake-amount: uint,
    votes-support: uint,
    votes-reject: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map stakeholder-votes
  { standard-id: uint, voter: principal }
  { voted: bool, vote-weight: uint }
)

(define-map dispute-votes
  { dispute-id: uint, voter: principal }
  { voted: bool, supports-challenge: bool }
)

(define-map governance-tokens
  { holder: principal }
  { balance: uint }
)

(define-map ethical-categories
  { category: (string-ascii 50) }
  { active: bool, standard-count: uint }
)

(define-map model-reports
  { model-hash: (buff 32), reporter: principal }
  { 
    reason: (string-ascii 200),
    severity: uint,
    reported-at: uint,
    resolved: bool
  }
)

(define-map improvement-proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    votes-for: uint,
    votes-against: uint,
    funding-requested: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

;; Initialize with ethical categories and governance tokens
(define-public (initialize)
  (begin
    (map-set ethical-categories { category: "bias-fairness" } { active: true, standard-count: u0 })
    (map-set ethical-categories { category: "privacy-protection" } { active: true, standard-count: u0 })
    (map-set ethical-categories { category: "transparency" } { active: true, standard-count: u0 })
    (map-set ethical-categories { category: "safety-security" } { active: true, standard-count: u0 })
    (map-set ethical-categories { category: "accountability" } { active: true, standard-count: u0 })
    (map-set governance-tokens { holder: CONTRACT-OWNER } { balance: u1000000 })
    (ok true)
  )
)

;; Propose new ethical standard with expiry
(define-public (propose-standard 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (category (string-ascii 50)))
  (let
    (
      (standard-id (+ (var-get standard-count) u1))
      (category-check (unwrap! (map-get? ethical-categories { category: category }) ERR-MODEL-NOT-FOUND))
      (proposer-tokens (default-to { balance: u0 } (map-get? governance-tokens { holder: tx-sender })))
      (expires-at (+ block-height (var-get challenge-period)))
    )
    (asserts! (get active category-check) ERR-NOT-AUTHORIZED)
    (asserts! (> (get balance proposer-tokens) u100) ERR-INSUFFICIENT-STAKE)
    
    (map-set ethical-standards
      { standard-id: standard-id }
      {
        title: title,
        description: description,
        category: category,
        proposer: tx-sender,
        votes-for: u0,
        votes-against: u0,
        status: "proposed",
        created-at: block-height,
        expires-at: expires-at
      }
    )
    
    ;; Update category counter
    (map-set ethical-categories 
      { category: category }
      (merge category-check { standard-count: (+ (get standard-count category-check) u1) })
    )
    
    (var-set standard-count standard-id)
    (ok standard-id)
  )
)

;; Vote on ethical standard with time check
(define-public (vote-on-standard (standard-id uint) (support bool))
  (let
    (
      (standard (unwrap! (map-get? ethical-standards { standard-id: standard-id }) ERR-MODEL-NOT-FOUND))
      (voter-tokens (default-to { balance: u0 } (map-get? governance-tokens { holder: tx-sender })))
      (existing-vote (map-get? stakeholder-votes { standard-id: standard-id, voter: tx-sender }))
      (vote-weight (get balance voter-tokens))
    )
    (asserts! (> vote-weight u0) ERR-INSUFFICIENT-STAKE)
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (is-eq (get status standard) "proposed") ERR-NOT-AUTHORIZED)
    (asserts! (< block-height (get expires-at standard)) ERR-PROPOSAL-EXPIRED)
    
    (map-set stakeholder-votes
      { standard-id: standard-id, voter: tx-sender }
      { voted: true, vote-weight: vote-weight }
    )
    
    (if support
      (map-set ethical-standards
        { standard-id: standard-id }
        (merge standard { votes-for: (+ (get votes-for standard) vote-weight) })
      )
      (map-set ethical-standards
        { standard-id: standard-id }
        (merge standard { votes-against: (+ (get votes-against standard) vote-weight) })
      )
    )
    
    (ok true)
  )
)

;; Finalize standard after voting period
(define-public (finalize-standard (standard-id uint))
  (let
    (
      (standard (unwrap! (map-get? ethical-standards { standard-id: standard-id }) ERR-MODEL-NOT-FOUND))
      (threshold (var-get governance-threshold))
    )
    (asserts! (is-eq (get status standard) "proposed") ERR-NOT-AUTHORIZED)
    (asserts! (>= block-height (get expires-at standard)) ERR-PROPOSAL-EXPIRED)
    
    (if (and (> (get votes-for standard) (get votes-against standard))
             (> (get votes-for standard) threshold))
      (map-set ethical-standards
        { standard-id: standard-id }
        (merge standard { status: "approved" })
      )
      (map-set ethical-standards
        { standard-id: standard-id }
        (merge standard { status: "rejected" })
      )
    )
    
    (ok true)
  )
)