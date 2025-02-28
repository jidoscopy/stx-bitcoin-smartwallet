;; title: enhanced-stx-bitcoin-smart-wallet-manual-height

;; Bitcoin Smart Wallet
;; Implements time-locked savings, split payments, emergency withdrawal functionality,
;; recurring payments, allowance system, and multi-signature authorization

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_TIME (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_INVALID_RECIPIENT (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_EMERGENCY_NOT_ACTIVE (err u105))
(define-constant ERR_ALLOWANCE_EXCEEDED (err u106))
(define-constant ERR_INSUFFICIENT_SIGNATURES (err u107))
(define-constant ERR_ALREADY_EXECUTED (err u108))
(define-constant ERR_PAYMENT_INACTIVE (err u109))
(define-constant ERR_INVALID_FREQUENCY (err u110))

;; Data variables
(define-data-var minimum-lock-period uint u1440) ;; minimum lock period in blocks (approximately 10 days)
(define-data-var emergency-withdrawal-fee uint u5) ;; 5% fee for emergency withdrawals
(define-data-var current-block-height uint u0)
(define-data-var transaction-counter uint u0)

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

;; NEW: Recurring payment map
(define-map recurring-payments
    { owner: principal, payment-id: uint }
    {
        recipient: principal,
        amount: uint,
        frequency: uint, ;; in blocks
        last-payment-height: uint,
        end-height: (optional uint),
        is-active: bool
    }
)

;; NEW: Allowance system map
(define-map allowances
    { owner: principal, spender: principal }
    {
        amount: uint,
        expiry-height: (optional uint)
    }
)

;; NEW: Multi-signature transaction map
(define-map multi-sig-transactions
    { tx-id: uint }
    {
        owner: principal,
        required-signatures: uint,
        signers: (list 10 principal),
        signatures: (list 10 principal),
        recipient: principal,
        amount: uint,
        memo: (optional (buff 34)),
        expiry-height: uint,
        executed: bool
    }
)

;; NEW: Multi-signature settings map
(define-map multi-sig-settings
    principal
    {
        signers: (list 10 principal),
        required-signatures: uint,
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

;; NEW: Recurring payment read-only functions
(define-read-only (get-recurring-payment (owner principal) (payment-id uint))
    (map-get? recurring-payments { owner: owner, payment-id: payment-id }))

(define-read-only (get-allowance (owner principal) (spender principal))
    (default-to u0 
        (get amount (map-get? allowances { owner: owner, spender: spender }))))

(define-read-only (get-multi-sig-transaction (tx-id uint))
    (map-get? multi-sig-transactions { tx-id: tx-id }))

(define-read-only (get-multi-sig-settings (owner principal))
    (map-get? multi-sig-settings owner))

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

;;  Recurring payment functions
(define-public (create-recurring-payment 
    (recipient principal) 
    (amount uint) 
    (frequency uint)
    (end-height (optional uint)))
    (let
        (
            (payment-id (var-get transaction-counter))
            (current-height (var-get current-block-height))
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> frequency u0) ERR_INVALID_FREQUENCY)
        (asserts! (not (is-eq recipient tx-sender)) ERR_INVALID_RECIPIENT)

        ;; Increment transaction counter
        (var-set transaction-counter (+ payment-id u1))

        (ok (map-set recurring-payments 
            { owner: tx-sender, payment-id: payment-id }
            {
                recipient: recipient,
                amount: amount,
                frequency: frequency,
                last-payment-height: current-height,
                end-height: end-height,
                is-active: true
            }))))

(define-public (execute-recurring-payment (payment-id uint))
    (let
        (
            (current-height (var-get current-block-height))
            (payment-data (unwrap! (map-get? recurring-payments { owner: tx-sender, payment-id: payment-id }) ERR_NOT_AUTHORIZED))
            (recipient (get recipient payment-data))
            (amount (get amount payment-data))
            (frequency (get frequency payment-data))
            (last-payment (get last-payment-height payment-data))
            (end-height (get end-height payment-data))
            (next-payment-height (+ last-payment frequency))
        )
        ;; Check if payment is active
        (asserts! (get is-active payment-data) ERR_PAYMENT_INACTIVE)

        ;; Check if payment is due
        (asserts! (>= current-height next-payment-height) ERR_INVALID_TIME)

        ;; Check if payment has expired
        (asserts! (or (is-none end-height) (<= current-height (unwrap! end-height ERR_PAYMENT_INACTIVE))) ERR_PAYMENT_INACTIVE)

        ;; Check balance
        (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)

        ;; Transfer funds
        (try! (stx-transfer? amount tx-sender recipient))

        ;; Update last payment height
        (ok (map-set recurring-payments
            { owner: tx-sender, payment-id: payment-id }
            (merge payment-data { last-payment-height: current-height })))))

(define-public (cancel-recurring-payment (payment-id uint))
    (let
        (
            (payment-data (unwrap! (map-get? recurring-payments { owner: tx-sender, payment-id: payment-id }) ERR_NOT_AUTHORIZED))
        )
        (ok (map-set recurring-payments
            { owner: tx-sender, payment-id: payment-id }
            (merge payment-data { is-active: false })))))

;;  Allowance system
(define-public (approve (spender principal) (amount uint) (expiry (optional uint)))
    (let
        (
            (current-height (var-get current-block-height))
            (expiry-height (match expiry
                height (some height)
                (some (+ current-height (var-get minimum-lock-period)))))
        )
        (ok (map-set allowances
            { owner: tx-sender, spender: spender }
            {
                amount: amount,
                expiry-height: expiry-height
            }))))

(define-public (transfer-from (owner principal) (recipient principal) (amount uint))
    (let
        (
            (current-height (var-get current-block-height))
            (allowance-data (unwrap! (map-get? allowances { owner: owner, spender: tx-sender }) ERR_NOT_AUTHORIZED))
            (allowance-amount (get amount allowance-data))
            (expiry-height (get expiry-height allowance-data))
        )
        ;; Check allowance amount
        (asserts! (>= allowance-amount amount) ERR_ALLOWANCE_EXCEEDED)

        ;; Check if allowance has expired
        (asserts! (or 
                    (is-none expiry-height) 
                    (< current-height (unwrap! expiry-height ERR_NOT_AUTHORIZED))) 
                ERR_NOT_AUTHORIZED)

        ;; Transfer funds from owner
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))

        ;; Update allowance
        (ok (map-set allowances
            { owner: owner, spender: tx-sender }
            {
                amount: (- allowance-amount amount),
                expiry-height: expiry-height
            }))))

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

(define-private (process-individual-payment
    (recipient principal)
    (percentage uint)
    (total-amount uint))
    (if (and (> percentage u0) (not (is-eq recipient tx-sender)))
        (let
            ((payment-amount (/ (* total-amount percentage) u100)))
            (match (as-contract (stx-transfer? payment-amount tx-sender recipient))
                success (ok true)
                error (err error)))
        (ok false)))
