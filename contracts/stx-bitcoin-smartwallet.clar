;; title: improved-stx-bitcoin-smart-wallet-manual-height

;; Bitcoin Smart Wallet
;; Implements time-locked savings, split payments, and emergency withdrawal functionality

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_TIME (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_INVALID_RECIPIENT (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_EMERGENCY_NOT_ACTIVE (err u105))

;; Data variables
(define-data-var minimum-lock-period uint u1440) ;; minimum lock period in blocks (approximately 10 days)
(define-data-var emergency-withdrawal-fee uint u5) ;; 5% fee for emergency withdrawals
(define-data-var current-block-height uint u0)

(define-map time-locked-savings 
    principal 
    {
        amount: uint,
        unlock-height: uint,
        is-active: bool,
        emergency-contact: (optional principal)
    }
)

(define-map split-payment-settings
    principal
    {
        recipients: (list 10 principal),
        percentages: (list 10 uint),
        is-active: bool
    }
)

;; Read-only functions
(define-read-only (get-balance (user principal))
    (default-to u0 
        (get amount (map-get? time-locked-savings user))))

(define-read-only (get-unlock-height (user principal))
    (default-to u0 
        (get unlock-height (map-get? time-locked-savings user))))

(define-read-only (get-split-payment-info (user principal))
    (map-get? split-payment-settings user))

(define-read-only (get-emergency-contact (user principal))
    (get emergency-contact (default-to 
        { amount: u0, unlock-height: u0, is-active: false, emergency-contact: none }
        (map-get? time-locked-savings user))))

(define-read-only (get-current-block-height)
    (var-get current-block-height))

;; Time-locked savings functions
(define-public (create-time-lock (amount uint) (lock-blocks uint) (emergency-contact (optional principal)))
    (let
        (
            (unlock-at (+ (var-get current-block-height) lock-blocks))
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= lock-blocks (var-get minimum-lock-period)) ERR_INVALID_TIME)
        (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (ok (map-set time-locked-savings tx-sender
            {
                amount: amount,
                unlock-height: unlock-at,
                is-active: true,
                emergency-contact: emergency-contact
            }))))

(define-public (withdraw)
    (let
        (
            (savings-data (unwrap! (map-get? time-locked-savings tx-sender) ERR_NOT_AUTHORIZED))
            (amount (get amount savings-data))
            (unlock-height (get unlock-height savings-data))
        )
        (asserts! (get is-active savings-data) ERR_NOT_AUTHORIZED)
        (asserts! (>= (var-get current-block-height) unlock-height) ERR_INVALID_TIME)
        (map-delete time-locked-savings tx-sender)
        (as-contract (stx-transfer? amount tx-sender tx-sender))))

(define-public (emergency-withdraw)
    (let
        (
            (savings-data (unwrap! (map-get? time-locked-savings tx-sender) ERR_NOT_AUTHORIZED))
            (amount (get amount savings-data))
            (fee-amount (/ (* amount (var-get emergency-withdrawal-fee)) u100))
            (withdrawal-amount (- amount fee-amount))
        )
        (asserts! (get is-active savings-data) ERR_NOT_AUTHORIZED)
        (asserts! (< (var-get current-block-height) (get unlock-height savings-data)) ERR_EMERGENCY_NOT_ACTIVE)
        (map-delete time-locked-savings tx-sender)
        (as-contract (begin
            (try! (stx-transfer? withdrawal-amount tx-sender tx-sender))
            (stx-transfer? fee-amount tx-sender CONTRACT_OWNER)))))

;; Split payment functions
(define-public (set-split-payment 
    (recipients (list 10 principal))
    (percentages (list 10 uint)))
    (begin
        (asserts! (is-eq (len recipients) (len percentages)) ERR_INVALID_RECIPIENT)
        (asserts! (is-valid-percentage-sum percentages) ERR_INVALID_RECIPIENT)
        (ok (map-set split-payment-settings tx-sender
            {
                recipients: recipients,
                percentages: percentages,
                is-active: true
            }))))

(define-public (execute-split-payment (amount uint))
    (let
        (
            (split-data (unwrap! (map-get? split-payment-settings tx-sender) ERR_NOT_AUTHORIZED))
            (recipients (get recipients split-data))
            (percentages (get percentages split-data))
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (get is-active split-data) ERR_NOT_AUTHORIZED)
        (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (process-split-payments amount recipients percentages)))

;; Helper functions
(define-private (is-valid-percentage-sum (percentages (list 10 uint)))
    (is-eq (fold + percentages u0) u100))

(define-private (process-split-payments 
    (total-amount uint)
    (recipients (list 10 principal))
    (percentages (list 10 uint)))
    (begin
        (map process-individual-payment
            recipients
            percentages
            (list u10 total-amount))
        (ok true)))
