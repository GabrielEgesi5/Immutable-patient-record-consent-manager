;; title: IPRCM
;; version: 1.0.0
;; summary: Immutable Patient Record Consent Manager
;; description: A smart contract for managing patient record access permissions

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_INPUT (err u103))
(define-constant ERR_CONSENT_EXPIRED (err u104))
(define-constant ERR_CONSENT_REVOKED (err u105))

(define-data-var next-record-id uint u1)
(define-data-var next-consent-id uint u1)

(define-map patients
    principal
    {
        name: (string-ascii 50),
        registered-at: uint,
        active: bool
    }
)

(define-map healthcare-providers
    principal
    {
        name: (string-ascii 50),
        license-number: (string-ascii 20),
        registered-at: uint,
        verified: bool
    }
)

(define-map patient-records
    uint
    {
        patient: principal,
        record-type: (string-ascii 30),
        record-hash: (buff 32),
        created-at: uint,
        provider: principal
    }
)

(define-map consent-permissions
    uint
    {
        patient: principal,
        provider: principal,
        record-type: (optional (string-ascii 30)),
        granted-at: uint,
        expires-at: (optional uint),
        active: bool
    }
)

(define-map patient-consents
    {patient: principal, provider: principal}
    (list 50 uint)
)

(define-map provider-patients
    principal
    (list 100 principal)
)

(define-map record-owners
    uint
    principal
)

(define-public (register-patient (name (string-ascii 50)))
    (begin
        (asserts! (>= (len name) u1) ERR_INVALID_INPUT)
        (asserts! (is-none (map-get? patients tx-sender)) ERR_ALREADY_EXISTS)
        
        (map-set patients tx-sender {
            name: name,
            registered-at: stacks-block-height,
            active: true
        })
        
        (ok true)
    )
)

(define-public (register-provider (name (string-ascii 50)) (license-number (string-ascii 20)))
    (begin
        (asserts! (>= (len name) u1) ERR_INVALID_INPUT)
        (asserts! (>= (len license-number) u1) ERR_INVALID_INPUT)
        (asserts! (is-none (map-get? healthcare-providers tx-sender)) ERR_ALREADY_EXISTS)
        
        (map-set healthcare-providers tx-sender {
            name: name,
            license-number: license-number,
            registered-at: stacks-block-height,
            verified: false
        })
        
        (ok true)
    )
)

(define-public (verify-provider (provider principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (match (map-get? healthcare-providers provider)
            provider-data
            (begin
                (map-set healthcare-providers provider (merge provider-data {verified: true}))
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (add-patient-record (record-type (string-ascii 30)) (record-hash (buff 32)))
    (let 
        (
            (record-id (var-get next-record-id))
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (>= (len record-type) u1) ERR_INVALID_INPUT)
        
        (map-set patient-records record-id {
            patient: tx-sender,
            record-type: record-type,
            record-hash: record-hash,
            created-at: stacks-block-height,
            provider: tx-sender
        })
        
        (map-set record-owners record-id tx-sender)
        (var-set next-record-id (+ record-id u1))
        
        (ok record-id)
    )
)

(define-public (grant-consent (provider principal) (record-type (optional (string-ascii 30))) (expires-at (optional uint)))
    (let
        (
            (consent-id (var-get next-consent-id))
            (consent-key {patient: tx-sender, provider: provider})
            (existing-consents (default-to (list) (map-get? patient-consents consent-key)))
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? healthcare-providers provider)) ERR_NOT_FOUND)
        
        (unwrap! (match (map-get? healthcare-providers provider)
            provider-data
            (begin
                (asserts! (get verified provider-data) ERR_UNAUTHORIZED)
                (ok true)
            )
            ERR_NOT_FOUND
        ) ERR_NOT_FOUND)
        
        (map-set consent-permissions consent-id {
            patient: tx-sender,
            provider: provider,
            record-type: record-type,
            granted-at: stacks-block-height,
            expires-at: expires-at,
            active: true
        })
        
        (map-set patient-consents consent-key (unwrap-panic (as-max-len? (append existing-consents consent-id) u50)))
        
        (let
            (
                (provider-patient-list (default-to (list) (map-get? provider-patients provider)))
            )
            (if (is-none (index-of provider-patient-list tx-sender))
                (map-set provider-patients provider (unwrap-panic (as-max-len? (append provider-patient-list tx-sender) u100)))
                true
            )
        )
        
        (var-set next-consent-id (+ consent-id u1))
        (ok consent-id)
    )
)

(define-public (revoke-consent (consent-id uint))
    (match (map-get? consent-permissions consent-id)
        consent-data
        (begin
            (asserts! (is-eq (get patient consent-data) tx-sender) ERR_UNAUTHORIZED)
            
            (map-set consent-permissions consent-id (merge consent-data {active: false}))
            (ok true)
        )
        ERR_NOT_FOUND
    )
)

(define-public (revoke-all-consents (provider principal))
    (let
        (
            (consent-key {patient: tx-sender, provider: provider})
            (consent-ids (default-to (list) (map-get? patient-consents consent-key)))
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        
        (fold revoke-consent-helper consent-ids true)
        (ok true)
    )
)

(define-private (revoke-consent-helper (consent-id uint) (acc bool))
    (match (map-get? consent-permissions consent-id)
        consent-data
        (if (is-eq (get patient consent-data) tx-sender)
            (begin
                (map-set consent-permissions consent-id (merge consent-data {active: false}))
                acc
            )
            acc
        )
        acc
    )
)

(define-read-only (has-access (patient principal) (provider principal) (record-type (optional (string-ascii 30))))
    (let
        (
            (consent-key {patient: patient, provider: provider})
            (consent-ids (default-to (list) (map-get? patient-consents consent-key)))
        )
        (> (len (filter is-valid-consent consent-ids)) u0)
    )
)

(define-private (is-valid-consent (consent-id uint))
    (match (map-get? consent-permissions consent-id)
        consent-data
        (and
            (get active consent-data)
            (match (get expires-at consent-data)
                expiry (< stacks-block-height expiry)
                true
            )
        )
        false
    )
)

(define-read-only (get-patient-info (patient principal))
    (map-get? patients patient)
)

(define-read-only (get-provider-info (provider principal))
    (map-get? healthcare-providers provider)
)

(define-read-only (get-record-info (record-id uint))
    (map-get? patient-records record-id)
)

(define-read-only (get-consent-info (consent-id uint))
    (map-get? consent-permissions consent-id)
)

(define-read-only (get-patient-consents (patient principal) (provider principal))
    (map-get? patient-consents {patient: patient, provider: provider})
)

(define-read-only (get-provider-patients (provider principal))
    (map-get? provider-patients provider)
)

(define-read-only (is-consent-active (consent-id uint))
    (match (map-get? consent-permissions consent-id)
        consent-data
        (and
            (get active consent-data)
            (match (get expires-at consent-data)
                expiry (< stacks-block-height expiry)
                true
            )
        )
        false
    )
)

(define-read-only (get-record-owner (record-id uint))
    (map-get? record-owners record-id)
)

(define-read-only (get-contract-info)
    {
        next-record-id: (var-get next-record-id),
        next-consent-id: (var-get next-consent-id),
        contract-owner: CONTRACT_OWNER
    }
)
