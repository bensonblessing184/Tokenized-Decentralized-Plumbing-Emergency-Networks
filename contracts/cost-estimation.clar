;; Cost Estimation Contract
;; Provides transparent pricing for repair services

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INVALID_ESTIMATE (err u401))
(define-constant ERR_ESTIMATE_NOT_FOUND (err u402))
(define-constant ERR_INVALID_PARAMETERS (err u403))

;; Data Variables
(define-data-var next-estimate-id uint u1)
(define-data-var base-labor-rate uint u75) ;; $75 per hour (in cents)
(define-data-var emergency-multiplier uint u150) ;; 1.5x for emergency calls
(define-data-var total-estimates uint u0)

;; Data Maps
(define-map cost-estimates
  { estimate-id: uint }
  {
    customer: principal,
    job-type: (string-ascii 50),
    description: (string-ascii 200),
    labor-hours: uint,
    parts-cost: uint,
    labor-cost: uint,
    emergency-fee: uint,
    total-cost: uint,
    created-at: uint,
    valid-until: uint,
    accepted: bool,
    completed: bool
  }
)

(define-map service-rates
  { service-type: (string-ascii 50) }
  {
    base-rate: uint,
    complexity-multiplier: uint,
    typical-duration: uint,
    description: (string-ascii 200)
  }
)

(define-map pricing-history
  { history-id: uint }
  {
    estimate-id: uint,
    original-cost: uint,
    final-cost: uint,
    variance: int,
    completion-date: uint
  }
)

(define-map market-rates
  { rate-type: (string-ascii 30) }
  {
    current-rate: uint,
    last-updated: uint,
    trend: (string-ascii 20)
  }
)

;; Private Variables
(define-data-var next-history-id uint u1)

;; Private Functions
(define-private (is-authorized (user principal))
  (or (is-eq user CONTRACT_OWNER) (is-eq user tx-sender))
)

(define-private (calculate-emergency-fee (base-cost uint) (is-emergency bool))
  (if is-emergency
    (/ (* base-cost (var-get emergency-multiplier)) u100)
    u0
  )
)

(define-private (calculate-complexity-adjustment (base-cost uint) (complexity-level uint))
  (/ (* base-cost complexity-level) u100)
)

;; Public Functions

;; Initialize service rates
(define-public (set-service-rate (service-type (string-ascii 50)) (base-rate uint) (complexity-multiplier uint) (typical-duration uint) (description (string-ascii 200)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> base-rate u0) ERR_INVALID_PARAMETERS)

    (map-set service-rates
      { service-type: service-type }
      {
        base-rate: base-rate,
        complexity-multiplier: complexity-multiplier,
        typical-duration: typical-duration,
        description: description
      }
    )

    (ok true)
  )
)

;; Create cost estimate
(define-public (create-estimate (job-type (string-ascii 50)) (description (string-ascii 200)) (estimated-hours uint) (parts-cost uint) (is-emergency bool) (complexity-level uint))
  (let
    (
      (estimate-id (var-get next-estimate-id))
      (base-labor-cost (* estimated-hours (var-get base-labor-rate)))
      (complexity-adjusted-labor (calculate-complexity-adjustment base-labor-cost complexity-level))
      (emergency-fee (calculate-emergency-fee (+ complexity-adjusted-labor parts-cost) is-emergency))
      (total-cost (+ complexity-adjusted-labor parts-cost emergency-fee))
    )
    (asserts! (> estimated-hours u0) ERR_INVALID_PARAMETERS)
    (asserts! (>= complexity-level u100) ERR_INVALID_PARAMETERS) ;; Minimum 100% (no reduction)

    (map-set cost-estimates
      { estimate-id: estimate-id }
      {
        customer: tx-sender,
        job-type: job-type,
        description: description,
        labor-hours: estimated-hours,
        parts-cost: parts-cost,
        labor-cost: complexity-adjusted-labor,
        emergency-fee: emergency-fee,
        total-cost: total-cost,
        created-at: block-height,
        valid-until: (+ block-height u1008), ;; Valid for 1 week (1008 blocks)
        accepted: false,
        completed: false
      }
    )

    (var-set next-estimate-id (+ estimate-id u1))
    (var-set total-estimates (+ (var-get total-estimates) u1))

    (ok estimate-id)
  )
)

;; Accept estimate
(define-public (accept-estimate (estimate-id uint))
  (let
    (
      (estimate (unwrap! (map-get? cost-estimates { estimate-id: estimate-id }) ERR_ESTIMATE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get customer estimate)) ERR_UNAUTHORIZED)
    (asserts! (<= block-height (get valid-until estimate)) ERR_INVALID_ESTIMATE)
    (asserts! (not (get accepted estimate)) ERR_INVALID_ESTIMATE)

    (map-set cost-estimates
      { estimate-id: estimate-id }
      (merge estimate { accepted: true })
    )

    (ok true)
  )
)

;; Update estimate with final costs
(define-public (finalize-estimate (estimate-id uint) (actual-hours uint) (actual-parts-cost uint))
  (let
    (
      (estimate (unwrap! (map-get? cost-estimates { estimate-id: estimate-id }) ERR_ESTIMATE_NOT_FOUND))
      (actual-labor-cost (* actual-hours (var-get base-labor-rate)))
      (emergency-fee (get emergency-fee estimate))
      (final-total (+ actual-labor-cost actual-parts-cost emergency-fee))
      (history-id (var-get next-history-id))
      (variance (- (to-int final-total) (to-int (get total-cost estimate))))
    )
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
    (asserts! (get accepted estimate) ERR_INVALID_ESTIMATE)
    (asserts! (not (get completed estimate)) ERR_INVALID_ESTIMATE)

    ;; Update estimate
    (map-set cost-estimates
      { estimate-id: estimate-id }
      (merge estimate {
        labor-hours: actual-hours,
        parts-cost: actual-parts-cost,
        labor-cost: actual-labor-cost,
        total-cost: final-total,
        completed: true
      })
    )

    ;; Record pricing history
    (map-set pricing-history
      { history-id: history-id }
      {
        estimate-id: estimate-id,
        original-cost: (get total-cost estimate),
        final-cost: final-total,
        variance: variance,
        completion-date: block-height
      }
    )

    (var-set next-history-id (+ history-id u1))

    (ok final-total)
  )
)

;; Update market rates
(define-public (update-market-rate (rate-type (string-ascii 30)) (new-rate uint) (trend (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-rate u0) ERR_INVALID_PARAMETERS)

    (map-set market-rates
      { rate-type: rate-type }
      {
        current-rate: new-rate,
        last-updated: block-height,
        trend: trend
      }
    )

    (ok true)
  )
)

;; Update base labor rate
(define-public (set-base-labor-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-rate u0) ERR_INVALID_PARAMETERS)

    (var-set base-labor-rate new-rate)
    (ok true)
  )
)

;; Update emergency multiplier
(define-public (set-emergency-multiplier (new-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (>= new-multiplier u100) ERR_INVALID_PARAMETERS) ;; At least 100% (no discount)

    (var-set emergency-multiplier new-multiplier)
    (ok true)
  )
)

;; Read-only Functions

;; Get cost estimate
(define-read-only (get-estimate (estimate-id uint))
  (map-get? cost-estimates { estimate-id: estimate-id })
)

;; Get service rate
(define-read-only (get-service-rate (service-type (string-ascii 50)))
  (map-get? service-rates { service-type: service-type })
)

;; Get pricing history
(define-read-only (get-pricing-history (history-id uint))
  (map-get? pricing-history { history-id: history-id })
)

;; Get market rate
(define-read-only (get-market-rate (rate-type (string-ascii 30)))
  (map-get? market-rates { rate-type: rate-type })
)

;; Calculate quick estimate
(define-read-only (calculate-quick-estimate (service-type (string-ascii 50)) (parts-cost uint) (is-emergency bool))
  (match (map-get? service-rates { service-type: service-type })
    service-rate
    (let
      (
        (base-labor (get base-rate service-rate))
        (duration (get typical-duration service-rate))
        (labor-cost (* duration (var-get base-labor-rate)))
        (emergency-fee (calculate-emergency-fee (+ labor-cost parts-cost) is-emergency))
      )
      (some {
        labor-cost: labor-cost,
        parts-cost: parts-cost,
        emergency-fee: emergency-fee,
        total-cost: (+ labor-cost parts-cost emergency-fee),
        estimated-duration: duration
      })
    )
    none
  )
)

;; Get pricing statistics
(define-read-only (get-pricing-stats)
  {
    total-estimates: (var-get total-estimates),
    base-labor-rate: (var-get base-labor-rate),
    emergency-multiplier: (var-get emergency-multiplier),
    next-estimate-id: (var-get next-estimate-id)
  }
)
