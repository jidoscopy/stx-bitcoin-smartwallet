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
