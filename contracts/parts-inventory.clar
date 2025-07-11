;; Parts Inventory Contract
;; Manages common plumbing component availability

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_PART_NOT_FOUND (err u301))
(define-constant ERR_INSUFFICIENT_STOCK (err u302))
(define-constant ERR_INVALID_QUANTITY (err u303))
(define-constant ERR_SUPPLIER_NOT_FOUND (err u304))

;; Data Variables
(define-data-var next-part-id uint u1)
(define-data-var next-supplier-id uint u1)
(define-data-var total-parts uint u0)
(define-data-var total-suppliers uint u0)
(define-data-var low-stock-threshold uint u10)

;; Data Maps
(define-map parts
  { part-id: uint }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    description: (string-ascii 200),
    current-stock: uint,
    min-stock: uint,
    unit-cost: uint,
    supplier-id: uint,
    last-restocked: uint,
    total-used: uint
  }
)

(define-map suppliers
  { supplier-id: uint }
  {
    name: (string-ascii 100),
    contact: (string-ascii 100),
    address: (string-ascii 200),
    rating: uint,
    delivery-time: uint,
    active: bool
  }
)

(define-map part-reservations
  { reservation-id: uint }
  {
    part-id: uint,
    quantity: uint,
    reserved-by: principal,
    reserved-at: uint,
    expires-at: uint,
    fulfilled: bool
  }
)

(define-map inventory-transactions
  { transaction-id: uint }
  {
    part-id: uint,
    transaction-type: (string-ascii 20),
    quantity: uint,
    unit-cost: uint,
    timestamp: uint,
    reference: (string-ascii 100)
  }
)

;; Private Variables
(define-data-var next-reservation-id uint u1)
(define-data-var next-transaction-id uint u1)

;; Private Functions
(define-private (is-authorized (user principal))
  (or (is-eq user CONTRACT_OWNER) (is-eq user tx-sender))
)

(define-private (is-low-stock (current-stock uint) (min-stock uint))
  (<= current-stock min-stock)
)

;; Public Functions

;; Register a new supplier
(define-public (register-supplier (name (string-ascii 100)) (contact (string-ascii 100)) (address (string-ascii 200)) (delivery-time uint))
  (let
    (
      (supplier-id (var-get next-supplier-id))
    )
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)

    (map-set suppliers
      { supplier-id: supplier-id }
      {
        name: name,
        contact: contact,
        address: address,
        rating: u40, ;; Start with 4.0 rating (scaled by 10)
        delivery-time: delivery-time,
        active: true
      }
    )

    (var-set next-supplier-id (+ supplier-id u1))
    (var-set total-suppliers (+ (var-get total-suppliers) u1))

    (ok supplier-id)
  )
)

;; Add a new part to inventory
(define-public (add-part (name (string-ascii 100)) (category (string-ascii 50)) (description (string-ascii 200)) (initial-stock uint) (min-stock uint) (unit-cost uint) (supplier-id uint))
  (let
    (
      (part-id (var-get next-part-id))
      (transaction-id (var-get next-transaction-id))
    )
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> initial-stock u0) ERR_INVALID_QUANTITY)
    (asserts! (is-some (map-get? suppliers { supplier-id: supplier-id })) ERR_SUPPLIER_NOT_FOUND)

    ;; Add part
    (map-set parts
      { part-id: part-id }
      {
        name: name,
        category: category,
        description: description,
        current-stock: initial-stock,
        min-stock: min-stock,
        unit-cost: unit-cost,
        supplier-id: supplier-id,
        last-restocked: block-height,
        total-used: u0
      }
    )

    ;; Record transaction
    (map-set inventory-transactions
      { transaction-id: transaction-id }
      {
        part-id: part-id,
        transaction-type: "restock",
        quantity: initial-stock,
        unit-cost: unit-cost,
        timestamp: block-height,
        reference: "initial-stock"
      }
    )

    (var-set next-part-id (+ part-id u1))
    (var-set next-transaction-id (+ transaction-id u1))
    (var-set total-parts (+ (var-get total-parts) u1))

    (ok part-id)
  )
)

;; Reserve parts for a job
(define-public (reserve-parts (part-id uint) (quantity uint))
  (let
    (
      (part (unwrap! (map-get? parts { part-id: part-id }) ERR_PART_NOT_FOUND))
      (reservation-id (var-get next-reservation-id))
      (current-stock (get current-stock part))
    )
    (asserts! (> quantity u0) ERR_INVALID_QUANTITY)
    (asserts! (>= current-stock quantity) ERR_INSUFFICIENT_STOCK)

    ;; Update part stock
    (map-set parts
      { part-id: part-id }
      (merge part { current-stock: (- current-stock quantity) })
    )

    ;; Create reservation
    (map-set part-reservations
      { reservation-id: reservation-id }
      {
        part-id: part-id,
        quantity: quantity,
        reserved-by: tx-sender,
        reserved-at: block-height,
        expires-at: (+ block-height u144), ;; 24 hours (144 blocks)
        fulfilled: false
      }
    )

    (var-set next-reservation-id (+ reservation-id u1))

    (ok reservation-id)
  )
)

;; Fulfill reservation (use reserved parts)
(define-public (fulfill-reservation (reservation-id uint))
  (let
    (
      (reservation (unwrap! (map-get? part-reservations { reservation-id: reservation-id }) ERR_PART_NOT_FOUND))
      (part-id (get part-id reservation))
      (part (unwrap! (map-get? parts { part-id: part-id }) ERR_PART_NOT_FOUND))
      (transaction-id (var-get next-transaction-id))
    )
    (asserts! (is-eq tx-sender (get reserved-by reservation)) ERR_UNAUTHORIZED)
    (asserts! (not (get fulfilled reservation)) ERR_INVALID_QUANTITY)
    (asserts! (<= block-height (get expires-at reservation)) ERR_INVALID_QUANTITY)

    ;; Mark reservation as fulfilled
    (map-set part-reservations
      { reservation-id: reservation-id }
      (merge reservation { fulfilled: true })
    )

    ;; Update part usage stats
    (map-set parts
      { part-id: part-id }
      (merge part { total-used: (+ (get total-used part) (get quantity reservation)) })
    )

    ;; Record transaction
    (map-set inventory-transactions
      { transaction-id: transaction-id }
      {
        part-id: part-id,
        transaction-type: "usage",
        quantity: (get quantity reservation),
        unit-cost: (get unit-cost part),
        timestamp: block-height,
        reference: "reservation-fulfilled"
      }
    )

    (var-set next-transaction-id (+ transaction-id u1))

    (ok true)
  )
)

;; Restock parts
(define-public (restock-part (part-id uint) (quantity uint) (new-unit-cost uint))
  (let
    (
      (part (unwrap! (map-get? parts { part-id: part-id }) ERR_PART_NOT_FOUND))
      (transaction-id (var-get next-transaction-id))
    )
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> quantity u0) ERR_INVALID_QUANTITY)

    ;; Update part stock and cost
    (map-set parts
      { part-id: part-id }
      (merge part {
        current-stock: (+ (get current-stock part) quantity),
        unit-cost: new-unit-cost,
        last-restocked: block-height
      })
    )

    ;; Record transaction
    (map-set inventory-transactions
      { transaction-id: transaction-id }
      {
        part-id: part-id,
        transaction-type: "restock",
        quantity: quantity,
        unit-cost: new-unit-cost,
        timestamp: block-height,
        reference: "manual-restock"
      }
    )

    (var-set next-transaction-id (+ transaction-id u1))

    (ok true)
  )
)

;; Cancel expired reservations
(define-public (cancel-expired-reservation (reservation-id uint))
  (let
    (
      (reservation (unwrap! (map-get? part-reservations { reservation-id: reservation-id }) ERR_PART_NOT_FOUND))
      (part-id (get part-id reservation))
      (part (unwrap! (map-get? parts { part-id: part-id }) ERR_PART_NOT_FOUND))
    )
    (asserts! (> block-height (get expires-at reservation)) ERR_UNAUTHORIZED)
    (asserts! (not (get fulfilled reservation)) ERR_INVALID_QUANTITY)

    ;; Return stock
    (map-set parts
      { part-id: part-id }
      (merge part { current-stock: (+ (get current-stock part) (get quantity reservation)) })
    )

    ;; Mark reservation as fulfilled (cancelled)
    (map-set part-reservations
      { reservation-id: reservation-id }
      (merge reservation { fulfilled: true })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get part information
(define-read-only (get-part (part-id uint))
  (map-get? parts { part-id: part-id })
)

;; Get supplier information
(define-read-only (get-supplier (supplier-id uint))
  (map-get? suppliers { supplier-id: supplier-id })
)

;; Get reservation information
(define-read-only (get-reservation (reservation-id uint))
  (map-get? part-reservations { reservation-id: reservation-id })
)

;; Get transaction information
(define-read-only (get-transaction (transaction-id uint))
  (map-get? inventory-transactions { transaction-id: transaction-id })
)

;; Check if part is low stock
(define-read-only (is-part-low-stock (part-id uint))
  (match (map-get? parts { part-id: part-id })
    part (is-low-stock (get current-stock part) (get min-stock part))
    false
  )
)

;; Get inventory statistics
(define-read-only (get-inventory-stats)
  {
    total-parts: (var-get total-parts),
    total-suppliers: (var-get total-suppliers),
    low-stock-threshold: (var-get low-stock-threshold),
    next-part-id: (var-get next-part-id)
  }
)
