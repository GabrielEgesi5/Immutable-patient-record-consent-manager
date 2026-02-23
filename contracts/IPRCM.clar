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
(define-constant ERR_EMERGENCY_FORBIDDEN (err u106))
(define-constant ERR_TEMPLATE_NOT_ACTIVE (err u107))
(define-constant ERR_NOT_DELEGATE (err u108))
(define-constant ERR_DELEGATE_EXISTS (err u109))
(define-constant ERR_SELF_DELEGATION (err u110))
(define-constant ERR_NO_ACCESS (err u111))
(define-constant MAX_EMERGENCY_WINDOW u720)

(define-data-var next-record-id uint u1)
(define-data-var next-consent-id uint u1)
(define-data-var next-emergency-id uint u1)
(define-data-var next-template-id uint u1)
(define-data-var next-audit-id uint u1)

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

(define-map emergency-access
    uint
    {
        patient: principal,
        provider: principal,
        reason: (string-ascii 80),
        granted-at: uint,
        expires-at: uint,
        acknowledged: bool
    }
)

(define-map consent-templates
    uint
    {
        provider: principal,
        name: (string-ascii 50),
        description: (string-ascii 200),
        record-types: (list 10 (string-ascii 30)),
        default-duration: uint,
        created-at: uint,
        active: bool
    }
)

(define-map provider-templates
    principal
    (list 50 uint)
)

(define-map patient-delegates
    {patient: principal, delegate: principal}
    {
        granted-at: uint,
        can-grant: bool,
        can-revoke: bool,
        active: bool
    }
)

(define-map delegate-patients
    principal
    (list 20 principal)
)

(define-map audit-trail
    uint
    {
        patient: principal,
        provider: principal,
        record-id: uint,
        action: (string-ascii 20),
        logged-at: uint
    }
)

(define-map patient-audit-logs
    principal
    (list 200 uint)
)

(define-map provider-audit-logs
    principal
    (list 200 uint)
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

(define-public (request-emergency-access (patient principal) (reason (string-ascii 80)) (duration uint))
    (let
        (
            (emergency-id (var-get next-emergency-id))
        )
        (asserts! (is-some (map-get? patients patient)) ERR_NOT_FOUND)
        (asserts! (is-some (map-get? healthcare-providers tx-sender)) ERR_UNAUTHORIZED)
        
        (unwrap! (match (map-get? healthcare-providers tx-sender)
            provider-data
            (begin
                (asserts! (get verified provider-data) ERR_UNAUTHORIZED)
                (ok true)
            )
            ERR_UNAUTHORIZED
        ) ERR_UNAUTHORIZED)
        
        (asserts! (> duration u0) ERR_INVALID_INPUT)
        (asserts! (<= duration MAX_EMERGENCY_WINDOW) ERR_INVALID_INPUT)
        (asserts! (>= (len reason) u5) ERR_INVALID_INPUT)
        
        (map-set emergency-access emergency-id {
            patient: patient,
            provider: tx-sender,
            reason: reason,
            granted-at: stacks-block-height,
            expires-at: (+ stacks-block-height duration),
            acknowledged: false
        })
        
        (var-set next-emergency-id (+ emergency-id u1))
        (ok emergency-id)
    )
)

(define-public (acknowledge-emergency (emergency-id uint) (accept bool))
    (match (map-get? emergency-access emergency-id)
        emergency-data
        (begin
            (asserts! (is-eq (get patient emergency-data) tx-sender) ERR_UNAUTHORIZED)
            (asserts! (> stacks-block-height (get expires-at emergency-data)) ERR_EMERGENCY_FORBIDDEN)
            
            (map-set emergency-access emergency-id (merge emergency-data {acknowledged: true}))
            
            (if (not accept)
                (let
                    (
                        (provider (get provider emergency-data))
                        (consent-key {patient: tx-sender, provider: provider})
                    )
                    (unwrap-panic (revoke-all-consents provider))
                )
                true
            )
            
            (ok accept)
        )
        ERR_NOT_FOUND
    )
)

(define-public (create-consent-template (name (string-ascii 50)) (description (string-ascii 200)) (record-types (list 10 (string-ascii 30))) (default-duration uint))
    (let
        (
            (template-id (var-get next-template-id))
            (existing-templates (default-to (list) (map-get? provider-templates tx-sender)))
        )
        (asserts! (is-some (map-get? healthcare-providers tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (>= (len name) u1) ERR_INVALID_INPUT)
        (asserts! (>= (len description) u10) ERR_INVALID_INPUT)
        (asserts! (> (len record-types) u0) ERR_INVALID_INPUT)
        (asserts! (> default-duration u0) ERR_INVALID_INPUT)
        
        (unwrap! (match (map-get? healthcare-providers tx-sender)
            provider-data
            (begin
                (asserts! (get verified provider-data) ERR_UNAUTHORIZED)
                (ok true)
            )
            ERR_NOT_FOUND
        ) ERR_NOT_FOUND)
        
        (map-set consent-templates template-id {
            provider: tx-sender,
            name: name,
            description: description,
            record-types: record-types,
            default-duration: default-duration,
            created-at: stacks-block-height,
            active: true
        })
        
        (map-set provider-templates tx-sender (unwrap-panic (as-max-len? (append existing-templates template-id) u50)))
        (var-set next-template-id (+ template-id u1))
        
        (ok template-id)
    )
)

(define-public (use-consent-template (template-id uint) (custom-duration (optional uint)))
    (match (map-get? consent-templates template-id)
        template-data
        (let
            (
                (provider (get provider template-data))
                (duration (default-to (get default-duration template-data) custom-duration))
                (expires-at (some (+ stacks-block-height duration)))
            )
            (asserts! (get active template-data) ERR_TEMPLATE_NOT_ACTIVE)
            (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
            
            (fold grant-template-consent (get record-types template-data) {provider: provider, expires-at: expires-at, success: true})
            (ok template-id)
        )
        ERR_NOT_FOUND
    )
)

(define-private (grant-template-consent (record-type (string-ascii 30)) (data {provider: principal, expires-at: (optional uint), success: bool}))
    (if (get success data)
        (let
            (
                (consent-id (var-get next-consent-id))
                (consent-key {patient: tx-sender, provider: (get provider data)})
                (existing-consents (default-to (list) (map-get? patient-consents consent-key)))
            )
            (map-set consent-permissions consent-id {
                patient: tx-sender,
                provider: (get provider data),
                record-type: (some record-type),
                granted-at: stacks-block-height,
                expires-at: (get expires-at data),
                active: true
            })
            
            (map-set patient-consents consent-key (unwrap-panic (as-max-len? (append existing-consents consent-id) u50)))
            (var-set next-consent-id (+ consent-id u1))
            
            data
        )
        data
    )
)

(define-public (deactivate-template (template-id uint))
    (match (map-get? consent-templates template-id)
        template-data
        (begin
            (asserts! (is-eq (get provider template-data) tx-sender) ERR_UNAUTHORIZED)
            
            (map-set consent-templates template-id (merge template-data {active: false}))
            (ok true)
        )
        ERR_NOT_FOUND
    )
)

(define-public (assign-delegate (delegate principal) (can-grant bool) (can-revoke bool))
    (let
        (
            (delegate-key {patient: tx-sender, delegate: delegate})
            (existing-patients (default-to (list) (map-get? delegate-patients delegate)))
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (not (is-eq tx-sender delegate)) ERR_SELF_DELEGATION)
        (asserts! (is-none (map-get? patient-delegates delegate-key)) ERR_DELEGATE_EXISTS)
        
        (map-set patient-delegates delegate-key {
            granted-at: stacks-block-height,
            can-grant: can-grant,
            can-revoke: can-revoke,
            active: true
        })
        
        (map-set delegate-patients delegate (unwrap-panic (as-max-len? (append existing-patients tx-sender) u20)))
        (ok true)
    )
)

(define-public (remove-delegate (delegate principal))
    (let
        (
            (delegate-key {patient: tx-sender, delegate: delegate})
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        (match (map-get? patient-delegates delegate-key)
            delegate-data
            (begin
                (map-set patient-delegates delegate-key (merge delegate-data {active: false}))
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (update-delegate-permissions (delegate principal) (can-grant bool) (can-revoke bool))
    (let
        (
            (delegate-key {patient: tx-sender, delegate: delegate})
        )
        (asserts! (is-some (map-get? patients tx-sender)) ERR_UNAUTHORIZED)
        (match (map-get? patient-delegates delegate-key)
            delegate-data
            (begin
                (asserts! (get active delegate-data) ERR_NOT_DELEGATE)
                (map-set patient-delegates delegate-key (merge delegate-data {can-grant: can-grant, can-revoke: can-revoke}))
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (grant-consent-as-delegate (patient principal) (provider principal) (record-type (optional (string-ascii 30))) (expires-at (optional uint)))
    (let
        (
            (delegate-key {patient: patient, delegate: tx-sender})
            (consent-id (var-get next-consent-id))
            (consent-key {patient: patient, provider: provider})
            (existing-consents (default-to (list) (map-get? patient-consents consent-key)))
        )
        (match (map-get? patient-delegates delegate-key)
            delegate-data
            (begin
                (asserts! (get active delegate-data) ERR_NOT_DELEGATE)
                (asserts! (get can-grant delegate-data) ERR_UNAUTHORIZED)
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
                    patient: patient,
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
                    (if (is-none (index-of provider-patient-list patient))
                        (map-set provider-patients provider (unwrap-panic (as-max-len? (append provider-patient-list patient) u100)))
                        true
                    )
                )
                
                (var-set next-consent-id (+ consent-id u1))
                (ok consent-id)
            )
            ERR_NOT_DELEGATE
        )
    )
)

(define-public (revoke-consent-as-delegate (patient principal) (consent-id uint))
    (let
        (
            (delegate-key {patient: patient, delegate: tx-sender})
        )
        (match (map-get? patient-delegates delegate-key)
            delegate-data
            (begin
                (asserts! (get active delegate-data) ERR_NOT_DELEGATE)
                (asserts! (get can-revoke delegate-data) ERR_UNAUTHORIZED)
                
                (match (map-get? consent-permissions consent-id)
                    consent-data
                    (begin
                        (asserts! (is-eq (get patient consent-data) patient) ERR_UNAUTHORIZED)
                        (map-set consent-permissions consent-id (merge consent-data {active: false}))
                        (ok true)
                    )
                    ERR_NOT_FOUND
                )
            )
            ERR_NOT_DELEGATE
        )
    )
)

(define-private (is-emergency-active (patient principal) (provider principal))
    (get found (fold check-emergency-match (generate-emergency-ids) {patient: patient, provider: provider, found: false}))
)

(define-private (check-emergency-match (emergency-id uint) (data {patient: principal, provider: principal, found: bool}))
    (if (get found data)
        data
        (match (map-get? emergency-access emergency-id)
            emergency-data
            (if (and
                (is-eq (get patient data) (get patient emergency-data))
                (is-eq (get provider data) (get provider emergency-data))
                (< stacks-block-height (get expires-at emergency-data))
                (not (get acknowledged emergency-data)))
                (merge data {found: true})
                data)
            data
        )
    )
)

(define-private (generate-emergency-ids)
    (let
        (
            (total-emergencies (var-get next-emergency-id))
        )
        (if (> total-emergencies u0)
            (unwrap-panic (slice? (list 
                u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20 u21 u22 u23 u24 u25 u26 u27 u28 u29 u30 u31 u32 u33 u34 u35 u36 u37 u38 u39 u40 u41 u42 u43 u44 u45 u46 u47 u48 u49 u50 u51 u52 u53 u54 u55 u56 u57 u58 u59 u60 u61 u62 u63 u64 u65 u66 u67 u68 u69 u70 u71 u72 u73 u74 u75 u76 u77 u78 u79 u80 u81 u82 u83 u84 u85 u86 u87 u88 u89 u90 u91 u92 u93 u94 u95 u96 u97 u98 u99
            ) u0 total-emergencies))
            (list)
        )
    )
)

(define-read-only (has-access (patient principal) (provider principal) (record-type (optional (string-ascii 30))))
    (let
        (
            (consent-key {patient: patient, provider: provider})
            (consent-ids (default-to (list) (map-get? patient-consents consent-key)))
        )
        (or
            (> (len (filter is-valid-consent consent-ids)) u0)
            (is-emergency-active patient provider)
        )
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

(define-read-only (get-emergency-info (emergency-id uint))
    (map-get? emergency-access emergency-id)
)

(define-read-only (get-patient-emergencies (patient principal))
    (get ids (fold build-patient-emergency-list (generate-emergency-ids) {patient: patient, ids: (list)}))
)

(define-read-only (get-provider-emergencies (provider principal))
    (get ids (fold build-provider-emergency-list (generate-emergency-ids) {provider: provider, ids: (list)}))
)

(define-private (build-patient-emergency-list (emergency-id uint) (data {patient: principal, ids: (list 100 uint)}))
    (match (map-get? emergency-access emergency-id)
        emergency-data
        (if (is-eq (get patient data) (get patient emergency-data))
            (merge data {ids: (unwrap-panic (as-max-len? (append (get ids data) emergency-id) u100))})
            data)
        data
    )
)

(define-private (build-provider-emergency-list (emergency-id uint) (data {provider: principal, ids: (list 100 uint)}))
    (match (map-get? emergency-access emergency-id)
        emergency-data
        (if (is-eq (get provider data) (get provider emergency-data))
            (merge data {ids: (unwrap-panic (as-max-len? (append (get ids data) emergency-id) u100))})
            data)
        data
    )
)

(define-read-only (get-template-info (template-id uint))
    (map-get? consent-templates template-id)
)

(define-read-only (get-provider-templates (provider principal))
    (map-get? provider-templates provider)
)

(define-read-only (get-active-templates (provider principal))
    (let
        (
            (template-ids (default-to (list) (map-get? provider-templates provider)))
        )
        (filter is-template-active template-ids)
    )
)

(define-private (is-template-active (template-id uint))
    (match (map-get? consent-templates template-id)
        template-data (get active template-data)
        false
    )
)

(define-private (build-expiring-consent-list (consent-id uint) (data {window: uint, now: uint, ids: (list 50 uint)}))
    (match (map-get? consent-permissions consent-id)
        consent-data
        (let
            (
                (expires-at-opt (get expires-at consent-data))
            )
            (match expires-at-opt
                expiry
                (if (and
                        (get active consent-data)
                        (>= expiry (get now data))
                        (<= expiry (+ (get now data) (get window data))))
                    (merge data {ids: (unwrap-panic (as-max-len? (append (get ids data) consent-id) u50))})
                    data)
                data
            )
        )
        data
    )
)

(define-read-only (get-expiring-consents (patient principal) (provider principal) (window uint))
    (let
        (
            (consent-key {patient: patient, provider: provider})
            (consent-ids (default-to (list) (map-get? patient-consents consent-key)))
        )
        (get ids (fold build-expiring-consent-list consent-ids {window: window, now: stacks-block-height, ids: (list)}))
    )
)

(define-read-only (get-delegate-info (patient principal) (delegate principal))
    (map-get? patient-delegates {patient: patient, delegate: delegate})
)

(define-read-only (get-delegate-patients (delegate principal))
    (map-get? delegate-patients delegate)
)

(define-read-only (is-active-delegate (patient principal) (delegate principal))
    (match (map-get? patient-delegates {patient: patient, delegate: delegate})
        delegate-data (get active delegate-data)
        false
    )
)

(define-read-only (can-delegate-grant (patient principal) (delegate principal))
    (match (map-get? patient-delegates {patient: patient, delegate: delegate})
        delegate-data (and (get active delegate-data) (get can-grant delegate-data))
        false
    )
)

(define-read-only (can-delegate-revoke (patient principal) (delegate principal))
    (match (map-get? patient-delegates {patient: patient, delegate: delegate})
        delegate-data (and (get active delegate-data) (get can-revoke delegate-data))
        false
    )
)

(define-public (log-record-access (patient principal) (record-id uint) (action (string-ascii 20)))
    (let
        (
            (audit-id (var-get next-audit-id))
            (record-data (unwrap! (map-get? patient-records record-id) ERR_NOT_FOUND))
            (existing-patient-logs (default-to (list) (map-get? patient-audit-logs patient)))
            (existing-provider-logs (default-to (list) (map-get? provider-audit-logs tx-sender)))
        )
        (asserts! (is-some (map-get? healthcare-providers tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? patients patient)) ERR_NOT_FOUND)
        (asserts! (is-eq (get patient record-data) patient) ERR_UNAUTHORIZED)
        (asserts! (>= (len action) u1) ERR_INVALID_INPUT)
        (asserts! (has-access patient tx-sender none) ERR_NO_ACCESS)

        (map-set audit-trail audit-id {
            patient: patient,
            provider: tx-sender,
            record-id: record-id,
            action: action,
            logged-at: stacks-block-height
        })

        (map-set patient-audit-logs patient (unwrap-panic (as-max-len? (append existing-patient-logs audit-id) u200)))
        (map-set provider-audit-logs tx-sender (unwrap-panic (as-max-len? (append existing-provider-logs audit-id) u200)))
        (var-set next-audit-id (+ audit-id u1))

        (ok audit-id)
    )
)

(define-read-only (get-audit-entry (audit-id uint))
    (map-get? audit-trail audit-id)
)

(define-read-only (get-patient-audit-log (patient principal))
    (map-get? patient-audit-logs patient)
)

(define-read-only (get-provider-audit-log (provider principal))
    (map-get? provider-audit-logs provider)
)

(define-read-only (get-contract-info)
    {
        next-record-id: (var-get next-record-id),
        next-consent-id: (var-get next-consent-id),
        next-emergency-id: (var-get next-emergency-id),
        next-template-id: (var-get next-template-id),
        next-audit-id: (var-get next-audit-id),
        contract-owner: CONTRACT_OWNER
    }
)
