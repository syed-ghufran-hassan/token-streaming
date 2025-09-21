;; Stream contract (no runtime block globals)
;; All functions that need the current chain height accept it as a uint parameter.

;; error codes
(define-constant ERR_UNAUTHORIZED (err u0))
(define-constant ERR_INVALID_SIGNATURE (err u1))
(define-constant ERR_STREAM_STILL_ACTIVE (err u2))
(define-constant ERR_INVALID_STREAM_ID (err u3))

;; data vars
(define-data-var latest-stream-id uint u0)
(define-data-var nonce uint u0)

;; streams mapping
(define-map streams
  uint ;; stream-id
  {
    sender: principal,
    recipient: principal,
    balance: uint,
    withdrawn-balance: uint,
    payment-per-block: uint,
    timeframe: (tuple (start-block uint) (stop-block uint))
  }
)

;; Create a new stream
(define-public (stream-to
    (recipient principal)
    (initial-balance uint)
    (timeframe (tuple (start-block uint) (stop-block uint)))
    (payment-per-block uint)
  )
  (let (
    (stream {
      sender: contract-caller,
      recipient: recipient,
      balance: initial-balance,
      withdrawn-balance: u0,
      payment-per-block: payment-per-block,
      timeframe: timeframe
    })
    (current-stream-id (var-get latest-stream-id))
  )
    (try! (stx-transfer? initial-balance contract-caller (as-contract tx-sender)))
    (map-set streams current-stream-id stream)
    (var-set latest-stream-id (+ current-stream-id u1))
    (ok current-stream-id)
  )
)

;; Increase the locked STX balance for a stream
(define-public (refuel
    (stream-id uint)
    (amount uint)
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))
  )
    (asserts! (is-eq contract-caller (get sender stream)) ERR_UNAUTHORIZED)
    (try! (stx-transfer? amount contract-caller (as-contract tx-sender)))
    (map-set streams stream-id 
      (merge stream {balance: (+ (get balance stream) amount)})
    )
    (ok amount)
  )
)

;; ---------- PRIVATE helper: calculate block delta using supplied current-block ----------
(define-private (calculate-block-delta
    (timeframe (tuple (start-block uint) (stop-block uint)))
    (current-block uint)
  )
  (let (
    (start-block (get start-block timeframe))
    (stop-block (get stop-block timeframe))
  )
    (if (<= current-block start-block)
      u0
      (if (< current-block stop-block)
        (- current-block start-block)
        (- stop-block start-block)
      )
    )
  )
)

;; ---------- PRIVATE helper: compute balance for a party given current-block ----------
(define-private (balance-of-internal
    (stream-id uint)
    (who principal)
    (current-block uint)
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) u0))
    (block-delta (calculate-block-delta (get timeframe stream) current-block))
    (recipient-balance (* block-delta (get payment-per-block stream)))
  )
    (if (is-eq who (get recipient stream))
      (- recipient-balance (get withdrawn-balance stream))
      (if (is-eq who (get sender stream))
        (- (get balance stream) recipient-balance)
        u0
      )
    )
  )
)

;; ---------- READ-ONLY: balance-of (caller must provide current-block) ----------
(define-read-only (balance-of
    (stream-id uint)
    (who principal)
    (current-block uint)
  )
  (balance-of-internal stream-id who current-block)
)

;; Withdraw received tokens
;; NOTE: caller MUST pass current-block (off-chain or wallet code should supply latest chain height)
(define-public (withdraw
    (stream-id uint)
    (current-block uint)
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))
    (balance (balance-of-internal stream-id contract-caller current-block))
  )
    (asserts! (is-eq contract-caller (get recipient stream)) ERR_UNAUTHORIZED)
    (map-set streams stream-id 
      (merge stream {withdrawn-balance: (+ (get withdrawn-balance stream) balance)})
    )
    (try! (as-contract (stx-transfer? balance tx-sender (get recipient stream))))
    (ok balance)
  )
)

;; Withdraw excess locked tokens
;; NOTE: caller MUST pass current-block
(define-public (refund
    (stream-id uint)
    (current-block uint)
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))
    (balance (balance-of-internal stream-id (get sender stream) current-block))
  )
    (asserts! (is-eq contract-caller (get sender stream)) ERR_UNAUTHORIZED)
    (asserts! (< (get stop-block (get timeframe stream)) current-block) ERR_STREAM_STILL_ACTIVE)
    (map-set streams stream-id (merge stream {
        balance: (- (get balance stream) balance),
      }
    ))
    (try! (as-contract (stx-transfer? balance tx-sender (get sender stream))))
    (ok balance)
  )
)

;; Get hash of stream
(define-read-only (hash-stream
    (stream-id uint)
    (new-payment-per-block uint)
    (new-timeframe (tuple (start-block uint) (stop-block uint)))
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) (sha256 0)))
    (msg (concat 
           (concat 
             (unwrap-panic (to-consensus-buff? stream)) 
             (unwrap-panic (to-consensus-buff? new-payment-per-block))
           ) 
           (unwrap-panic (to-consensus-buff? new-timeframe))
         ))
  )
    (sha256 msg)
  )
)

;; Signature verification
(define-read-only (validate-signature 
    (hash (buff 32)) 
    (signature (buff 65)) 
    (signer principal)
  )
  (is-eq 
    (principal-of? (unwrap! (secp256k1-recover? hash signature) false)) 
    (ok signer)
  )
)

;; Update stream configuration
(define-public (update-details
    (stream-id uint)
    (payment-per-block uint)
    (timeframe (tuple (start-block uint) (stop-block uint)))
    (signer principal)
    (signature (buff 65))
  )
  (let (
    (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))  
  )
    (asserts! 
      (validate-signature (hash-stream stream-id payment-per-block timeframe) signature signer) 
      ERR_INVALID_SIGNATURE
    )
    (asserts!
      (or
        (and (is-eq (get sender stream) contract-caller) (is-eq (get recipient stream) signer))
        (and (is-eq (get sender stream) signer) (is-eq (get recipient stream) contract-caller))
      )
      ERR_UNAUTHORIZED
    )
    (map-set streams stream-id (merge stream {
        payment-per-block: payment-per-block,
        timeframe: timeframe
    }))
    (ok true)
  )
)
