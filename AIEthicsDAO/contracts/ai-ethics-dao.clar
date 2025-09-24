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

;; Become certified auditor by staking tokens
(define-public (become-auditor (stake-amount uint) (specializations (list 5 (string-ascii 50))))
  (begin
    (asserts! (>= stake-amount (var-get min-auditor-stake)) ERR-INSUFFICIENT-STAKE)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set certified-auditors
      { auditor: tx-sender }
      {
        stake-amount: stake-amount,
        completed-audits: u0,
        reputation-score: u100,
        specializations: specializations,
        active: true,
        slashed-amount: u0
      }
    )
    
    (ok true)
  )
)

;; Submit model for ethical audit with platform fee
(define-public (request-audit 
  (model-hash (buff 32))
  (model-name (string-ascii 100))
  (audit-payment uint))
  (let
    (
      (audit-id (+ (var-get audit-count) u1))
      (platform-fee (/ (* audit-payment (var-get audit-fee-percentage)) u100))
      (auditor-payment (- audit-payment platform-fee))
    )
    (asserts! (> audit-payment u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? audit-payment tx-sender (as-contract tx-sender)))
    
    (map-set model-audits
      { audit-id: audit-id }
      {
        model-hash: model-hash,
        model-name: model-name,
        auditor: CONTRACT-OWNER,
        compliance-score: u0,
        issues-found: u0,
        audit-report: 0x00,
        payment: auditor-payment,
        status: "pending",
        created-at: block-height,
        requester: tx-sender
      }
    )
    
    (var-set audit-count audit-id)
    (ok audit-id)
  )
)

;; Accept audit assignment
(define-public (accept-audit (audit-id uint))
  (let
    (
      (audit (unwrap! (map-get? model-audits { audit-id: audit-id }) ERR-MODEL-NOT-FOUND))
      (auditor (unwrap! (map-get? certified-auditors { auditor: tx-sender }) ERR-AUDITOR-NOT-FOUND))
    )
    (asserts! (get active auditor) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status audit) "pending") ERR-AUDIT-COMPLETE)
    
    (map-set model-audits
      { audit-id: audit-id }
      (merge audit { auditor: tx-sender, status: "in-progress" })
    )
    
    (ok true)
  )
)

;; Submit audit results
(define-public (submit-audit 
  (audit-id uint)
  (compliance-score uint)
  (issues-found uint)
  (audit-report (buff 32)))
  (let
    (
      (audit (unwrap! (map-get? model-audits { audit-id: audit-id }) ERR-MODEL-NOT-FOUND))
      (auditor (unwrap! (map-get? certified-auditors { auditor: tx-sender }) ERR-AUDITOR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get auditor audit)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status audit) "in-progress") ERR-AUDIT-COMPLETE)
    (asserts! (<= compliance-score u100) ERR-NOT-AUTHORIZED)
    
    ;; Pay auditor
    (try! (as-contract (stx-transfer? (get payment audit) tx-sender (get auditor audit))))
    
    ;; Update audit
    (map-set model-audits
      { audit-id: audit-id }
      (merge audit {
        compliance-score: compliance-score,
        issues-found: issues-found,
        audit-report: audit-report,
        status: "completed"
      })
    )
    
    ;; Update auditor stats
    (map-set certified-auditors
      { auditor: tx-sender }
      (merge auditor {
        completed-audits: (+ (get completed-audits auditor) u1),
        reputation-score: (+ (get reputation-score auditor) u5)
      })
    )
    
    (ok true)
  )
)

;; Challenge audit results
(define-public (challenge-audit 
  (audit-id uint)
  (reason (string-ascii 200))
  (stake-amount uint))
  (let
    (
      (audit (unwrap! (map-get? model-audits { audit-id: audit-id }) ERR-MODEL-NOT-FOUND))
      (dispute-id (+ (var-get dispute-count) u1))
    )
    (asserts! (is-eq (get status audit) "completed") ERR-NOT-AUTHORIZED)
    (asserts! (>= stake-amount u500) ERR-INSUFFICIENT-STAKE)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set audit-disputes
      { dispute-id: dispute-id }
      {
        audit-id: audit-id,
        challenger: tx-sender,
        reason: reason,
        stake-amount: stake-amount,
        votes-support: u0,
        votes-reject: u0,
        status: "active",
        created-at: block-height
      }
    )
    
    (var-set dispute-count dispute-id)
    (ok dispute-id)
  )
)

;; Report suspicious model
(define-public (report-model 
  (model-hash (buff 32))
  (reason (string-ascii 200))
  (severity uint))
  (let
    (
      (existing-report (map-get? model-reports { model-hash: model-hash, reporter: tx-sender }))
    )
    (asserts! (is-none existing-report) ERR-ALREADY-REPORTED)
    (asserts! (<= severity u5) ERR-INVALID-AMOUNT)
    
    (map-set model-reports
      { model-hash: model-hash, reporter: tx-sender }
      {
        reason: reason,
        severity: severity,
        reported-at: block-height,
        resolved: false
      }
    )
    
    (ok true)
  )
)

;; Submit improvement proposal
(define-public (submit-improvement-proposal
  (title (string-ascii 100))
  (description (string-ascii 500))
  (funding-requested uint))
  (let
    (
      (proposal-id (+ (var-get proposal-count) u1))
      (proposer-tokens (default-to { balance: u0 } (map-get? governance-tokens { holder: tx-sender })))
    )
    (asserts! (> (get balance proposer-tokens) u1000) ERR-INSUFFICIENT-STAKE)
    
    (map-set improvement-proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        votes-for: u0,
        votes-against: u0,
        funding-requested: funding-requested,
        status: "proposed",
        created-at: block-height
      }
    )
    
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; Slash auditor for misconduct
(define-public (slash-auditor (auditor principal) (slash-amount uint))
  (let
    (
      (auditor-info (unwrap! (map-get? certified-auditors { auditor: auditor }) ERR-AUDITOR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= slash-amount (get stake-amount auditor-info)) ERR-INVALID-AMOUNT)
    
    (map-set certified-auditors
      { auditor: auditor }
      (merge auditor-info {
        slashed-amount: (+ (get slashed-amount auditor-info) slash-amount),
        reputation-score: (if (> (get reputation-score auditor-info) u20) 
                            (- (get reputation-score auditor-info) u20) u0),
        active: (if (> slash-amount (/ (get stake-amount auditor-info) u2)) false (get active auditor-info))
      })
    )
    
    (ok true)
  )
)

;; Distribute governance tokens
(define-public (transfer-governance-tokens (recipient principal) (amount uint))
  (let
    (
      (sender-balance (get balance (get-governance-balance tx-sender)))
    )
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-STAKE)
    (map-set governance-tokens { holder: tx-sender } { balance: (- sender-balance amount) })
    (map-set governance-tokens 
      { holder: recipient } 
      { balance: (+ (get balance (get-governance-balance recipient)) amount) }
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-standard (standard-id uint))
  (map-get? ethical-standards { standard-id: standard-id })
)

(define-read-only (get-audit (audit-id uint))
  (map-get? model-audits { audit-id: audit-id })
)

(define-read-only (get-auditor (auditor principal))
  (map-get? certified-auditors { auditor: auditor })
)

(define-read-only (get-governance-balance (holder principal))
  (default-to { balance: u0 } (map-get? governance-tokens { holder: holder }))
)

(define-read-only (is-valid-category (category (string-ascii 50)))
  (default-to { active: false, standard-count: u0 } (map-get? ethical-categories { category: category }))
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? audit-disputes { dispute-id: dispute-id })
)

(define-read-only (get-model-report (model-hash (buff 32)) (reporter principal))
  (map-get? model-reports { model-hash: model-hash, reporter: reporter })
)

(define-read-only (get-improvement-proposal (proposal-id uint))
  (map-get? improvement-proposals { proposal-id: proposal-id })
)

(define-read-only (get-contract-stats)
  {
    total-standards: (var-get standard-count),
    total-audits: (var-get audit-count),
    total-disputes: (var-get dispute-count),
    min-auditor-stake: (var-get min-auditor-stake),
    governance-threshold: (var-get governance-threshold)
  }
)