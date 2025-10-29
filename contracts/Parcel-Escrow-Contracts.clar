(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-confirmed (err u103))
(define-constant err-already-refunded (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-expired (err u106))
(define-constant err-not-expired (err u107))
(define-constant err-invalid-verification (err u108))
(define-constant err-insufficient-funds (err u109))
(define-constant err-not-agreed (err u110))

(define-data-var next-escrow-id uint u1)
(define-data-var platform-fee-rate uint u250)
(define-data-var min-escrow-amount uint u1000000)
(define-data-var max-escrow-duration uint u144)

(define-map escrows uint 
  {
    sender: principal,
    recipient: principal,
    amount: uint,
    fee: uint,
    created-at: uint,
    expires-at: uint,
    status: (string-ascii 20),
    verification-code: (buff 32),
    delivery-confirmed: bool,
    refunded: bool
  })

(define-map user-escrows principal (list 100 uint))
(define-map verification-attempts uint uint)
(define-map mutual-consent uint {sender-agrees: bool, recipient-agrees: bool, action: (string-ascii 10)})

(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows escrow-id))

(define-read-only (get-user-escrows (user principal))
  (default-to (list) (map-get? user-escrows user)))

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate))

(define-read-only (get-min-escrow-amount)
  (var-get min-escrow-amount))

(define-read-only (get-max-escrow-duration)
  (var-get max-escrow-duration))

(define-read-only (get-next-escrow-id)
  (var-get next-escrow-id))

(define-read-only (is-escrow-expired (escrow-id uint))
  (match (map-get? escrows escrow-id)
    escrow-data (> stacks-block-height (get expires-at escrow-data))
    false))

(define-read-only (calculate-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000))

(define-read-only (get-verification-attempts (escrow-id uint))
  (default-to u0 (map-get? verification-attempts escrow-id)))

(define-read-only (get-mutual-consent-status (escrow-id uint))
  (map-get? mutual-consent escrow-id))

(define-private (generate-verification-code (escrow-id uint) (sender principal) (recipient principal))
  (sha256 (concat 
    (concat (unwrap-panic (to-consensus-buff? escrow-id))
            (unwrap-panic (to-consensus-buff? sender)))
    (concat (unwrap-panic (to-consensus-buff? recipient))
            (unwrap-panic (to-consensus-buff? stacks-block-height))))))

(define-private (add-to-user-escrows (user principal) (escrow-id uint))
  (let ((current-escrows (get-user-escrows user)))
    (map-set user-escrows user (unwrap-panic (as-max-len? (append current-escrows escrow-id) u100)))))

(define-private (transfer-stx-to-escrow (amount uint))
  (stx-transfer? amount tx-sender (as-contract tx-sender)))

(define-private (transfer-stx-from-escrow (amount uint) (recipient principal))
  (as-contract (stx-transfer? amount tx-sender recipient)))

(define-public (create-escrow (recipient principal) (amount uint) (duration-blocks uint))
  (let (
    (escrow-id (var-get next-escrow-id))
    (fee (calculate-fee amount))
    (total-amount (+ amount fee))
    (expires-at (+ stacks-block-height duration-blocks))
    (verification-code (generate-verification-code escrow-id tx-sender recipient))
  )
    (asserts! (>= amount (var-get min-escrow-amount)) err-invalid-amount)
    (asserts! (<= duration-blocks (var-get max-escrow-duration)) err-invalid-amount)
    (asserts! (not (is-eq tx-sender recipient)) err-unauthorized)
    (asserts! (>= (stx-get-balance tx-sender) total-amount) err-insufficient-funds)
    
    (try! (transfer-stx-to-escrow total-amount))
    
    (map-set escrows escrow-id {
      sender: tx-sender,
      recipient: recipient,
      amount: amount,
      fee: fee,
      created-at: stacks-block-height,
      expires-at: expires-at,
      status: "pending",
      verification-code: verification-code,
      delivery-confirmed: false,
      refunded: false
    })
    
    (add-to-user-escrows tx-sender escrow-id)
    (add-to-user-escrows recipient escrow-id)
    (var-set next-escrow-id (+ escrow-id u1))
    
    (ok escrow-id)))

(define-public (confirm-delivery (escrow-id uint) (verification-code (buff 32)))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
        (attempts (get-verification-attempts escrow-id)))
    
    (asserts! (is-eq tx-sender (get recipient escrow-data)) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    (asserts! (not (is-escrow-expired escrow-id)) err-expired)
    (asserts! (< attempts u5) err-invalid-verification)
    
    (if (is-eq verification-code (get verification-code escrow-data))
      true
      (begin
        (map-set verification-attempts escrow-id (+ attempts u1))
        (asserts! false err-invalid-verification)))
    
    (try! (transfer-stx-from-escrow (get amount escrow-data) (get recipient escrow-data)))
    
    (if (> (get fee escrow-data) u0)
      (try! (transfer-stx-from-escrow (get fee escrow-data) contract-owner))
      true)
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "completed",
      delivery-confirmed: true
    }))
    
    (ok true)))

(define-public (request-refund (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
    
    (asserts! (is-eq tx-sender (get sender escrow-data)) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    (asserts! (is-escrow-expired escrow-id) err-not-expired)
    
    (try! (transfer-stx-from-escrow (get amount escrow-data) (get sender escrow-data)))
    
    (if (> (get fee escrow-data) u0)
      (try! (transfer-stx-from-escrow (get fee escrow-data) contract-owner))
      true)
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "refunded",
      refunded: true
    }))
    
    (ok true)))

(define-public (cancel-escrow (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
    
    (asserts! (is-eq tx-sender (get sender escrow-data)) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    (asserts! (< stacks-block-height (+ (get created-at escrow-data) u6)) err-unauthorized)
    
    (try! (transfer-stx-from-escrow (+ (get amount escrow-data) (get fee escrow-data)) (get sender escrow-data)))
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "cancelled",
      refunded: true
    }))
    
    (ok true)))

(define-public (extend-escrow (escrow-id uint) (additional-blocks uint))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
    
    (asserts! (is-eq tx-sender (get sender escrow-data)) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    (asserts! (not (is-escrow-expired escrow-id)) err-expired)
    (asserts! (<= (+ (- (get expires-at escrow-data) stacks-block-height) additional-blocks) (var-get max-escrow-duration)) err-invalid-amount)
    
    (map-set escrows escrow-id (merge escrow-data {
      expires-at: (+ (get expires-at escrow-data) additional-blocks)
    }))
    
    (ok true)))

(define-public (update-verification-code (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
        (new-code (generate-verification-code escrow-id (get sender escrow-data) (get recipient escrow-data))))
    
    (asserts! (or (is-eq tx-sender (get sender escrow-data)) 
                  (is-eq tx-sender (get recipient escrow-data))) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    
    (map-set escrows escrow-id (merge escrow-data {
      verification-code: new-code
    }))
    
    (map-delete verification-attempts escrow-id)
    
    (ok new-code)))

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount)
    (var-set platform-fee-rate new-rate)
    (ok true)))

(define-public (set-min-escrow-amount (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set min-escrow-amount new-amount)
    (ok true)))

(define-public (set-max-escrow-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set max-escrow-duration new-duration)
    (ok true)))

(define-public (propose-mutual-resolution (escrow-id uint) (action (string-ascii 10)))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
        (is-sender (is-eq tx-sender (get sender escrow-data)))
        (is-recipient (is-eq tx-sender (get recipient escrow-data))))
    
    (asserts! (or is-sender is-recipient) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    (asserts! (or (is-eq action "release") (is-eq action "cancel")) err-invalid-amount)
    
    (map-set mutual-consent escrow-id {
      sender-agrees: is-sender,
      recipient-agrees: is-recipient,
      action: action
    })
    
    (ok true)))

(define-public (agree-to-resolution (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
        (consent-data (unwrap! (map-get? mutual-consent escrow-id) err-not-found))
        (is-sender (is-eq tx-sender (get sender escrow-data)))
        (is-recipient (is-eq tx-sender (get recipient escrow-data))))
    
    (asserts! (or is-sender is-recipient) err-unauthorized)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    
    (asserts! (not (and is-sender (get sender-agrees consent-data))) err-not-agreed)
    (asserts! (not (and is-recipient (get recipient-agrees consent-data))) err-not-agreed)
    
    (let ((updated-consent (merge consent-data {
            sender-agrees: (or (get sender-agrees consent-data) is-sender),
            recipient-agrees: (or (get recipient-agrees consent-data) is-recipient)
          })))
      
      (if (and (get sender-agrees updated-consent) (get recipient-agrees updated-consent))
        (begin
          (if (is-eq (get action consent-data) "release")
            (begin
              (try! (transfer-stx-from-escrow (get amount escrow-data) (get recipient escrow-data)))
              (if (> (get fee escrow-data) u0)
                (try! (transfer-stx-from-escrow (get fee escrow-data) contract-owner))
                true)
              (map-set escrows escrow-id (merge escrow-data {
                status: "mutual-release",
                delivery-confirmed: true
              })))
            (begin
              (try! (transfer-stx-from-escrow (+ (get amount escrow-data) (get fee escrow-data)) (get sender escrow-data)))
              (map-set escrows escrow-id (merge escrow-data {
                status: "mutual-cancel",
                refunded: true
              }))))
          (map-delete mutual-consent escrow-id)
          (ok true))
        (begin
          (map-set mutual-consent escrow-id updated-consent)
          (ok false))))))

(define-public (emergency-release (escrow-id uint) (to-recipient bool))
  (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get delivery-confirmed escrow-data)) err-already-confirmed)
    (asserts! (not (get refunded escrow-data)) err-already-refunded)
    
    (if to-recipient
      (begin
        (try! (transfer-stx-from-escrow (get amount escrow-data) (get recipient escrow-data)))
        (map-set escrows escrow-id (merge escrow-data {
          status: "emergency-released",
          delivery-confirmed: true
        })))
      (begin
        (try! (transfer-stx-from-escrow (get amount escrow-data) (get sender escrow-data)))
        (map-set escrows escrow-id (merge escrow-data {
          status: "emergency-refunded",
          refunded: true
        }))))
    
    (if (> (get fee escrow-data) u0)
      (try! (transfer-stx-from-escrow (get fee escrow-data) contract-owner))
      true)
    
    (ok true)))
