

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_PARAMETERS (err u400))
(define-constant ERR_DISPUTE_EXISTS (err u410))
(define-constant ERR_NOT_DISPUTABLE (err u411))
(define-constant ERR_INSUFFICIENT_BALANCE (err u412))
(define-constant ERR_INVALID_ROYALTY (err u413))
(define-constant ERR_NO_EARNINGS (err u414))

(define-non-fungible-token mindchain-ip uint)

(define-data-var token-id-nonce uint u1)
(define-data-var dispute-id-nonce uint u1)
(define-data-var contract-paused bool false)

(define-map ideas
  { idea-id: uint }
  {
    creator: principal,
    idea-hash: (buff 32),
    title: (string-ascii 100),
    timestamp: uint,
    block-height: uint,
    license-terms: (optional (string-ascii 500)),
    is-public: bool,
    dispute-count: uint,
    latest-version: uint
  }
)

(define-map idea-ownership
  { creator: principal, idea-hash: (buff 32) }
  { idea-id: uint, timestamp: uint }
)

(define-map disputes
  { dispute-id: uint }
  {
    idea-id: uint,
    challenger: principal,
    evidence-hash: (buff 32),
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    created-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map dispute-votes
  { dispute-id: uint, voter: principal }
  { vote: bool, timestamp: uint }
)

(define-map voter-reputation
  { voter: principal }
  { reputation: uint, total-votes: uint }
)

(define-map royalty-agreements
  { idea-id: uint }
  {
    royalty-rate: uint,
    total-earned: uint,
    total-withdrawn: uint,
    active: bool
  }
)

(define-map user-earnings
  { user: principal, idea-id: uint }
  {
    earned: uint,
    withdrawn: uint
  }
)

(define-map idea-versions
  { idea-id: uint, version: uint }
  {
    hash: (buff 32),
    timestamp: uint,
    changes: (string-ascii 200)
  }
)

(define-read-only (get-last-token-id)
  (ok (- (var-get token-id-nonce) u1))
)

(define-read-only (get-token-uri (token-id uint))
  (ok none)
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? mindchain-ip token-id))
)

(define-read-only (get-idea (idea-id uint))
  (map-get? ideas { idea-id: idea-id })
)

(define-read-only (get-idea-by-hash (creator principal) (idea-hash (buff 32)))
  (match (map-get? idea-ownership { creator: creator, idea-hash: idea-hash })
    ownership (get-idea (get idea-id ownership))
    none
  )
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-voter-reputation (voter principal))
  (default-to { reputation: u0, total-votes: u0 }
    (map-get? voter-reputation { voter: voter })
  )
)

(define-read-only (has-voted (dispute-id uint) (voter principal))
  (is-some (map-get? dispute-votes { dispute-id: dispute-id, voter: voter }))
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-royalty-agreement (idea-id uint))
  (map-get? royalty-agreements { idea-id: idea-id })
)

(define-read-only (get-user-earnings (user principal) (idea-id uint))
  (default-to { earned: u0, withdrawn: u0 }
    (map-get? user-earnings { user: user, idea-id: idea-id })
  )
)

(define-read-only (get-available-earnings (user principal) (idea-id uint))
  (let ((earnings (get-user-earnings user idea-id)))
    (- (get earned earnings) (get withdrawn earnings))
  )
)

(define-read-only (get-idea-version (idea-id uint) (version uint))
  (map-get? idea-versions { idea-id: idea-id, version: version })
)

(define-private (increment-token-id)
  (let ((current-id (var-get token-id-nonce)))
    (var-set token-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (increment-dispute-id)
  (let ((current-id (var-get dispute-id-nonce)))
    (var-set dispute-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (validate-idea-params (title (string-ascii 100)) (idea-hash (buff 32)))
  (and
    (> (len title) u0)
    (< (len title) u101)
    (is-eq (len idea-hash) u32)
  )
)

(define-private (validate-royalty-rate (rate uint))
  (and (> rate u0) (<= rate u10000))
)

(define-private (validate-version-params (changes (string-ascii 200)) (new-hash (buff 32)))
  (and (> (len changes) u0) (< (len changes) u201) (is-eq (len new-hash) u32))
)

(define-public (submit-idea
  (title (string-ascii 100))
  (idea-hash (buff 32))
  (license-terms (optional (string-ascii 500)))
  (is-public bool)
)
  (let
    (
      (idea-id (increment-token-id))
      (current-height stacks-block-height)
      (current-time stacks-block-height)
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (validate-idea-params title idea-hash) ERR_INVALID_PARAMETERS)
    (asserts!
      (is-none (map-get? idea-ownership { creator: tx-sender, idea-hash: idea-hash }))
      ERR_ALREADY_EXISTS
    )

    (try! (nft-mint? mindchain-ip idea-id tx-sender))

    (map-set ideas
      { idea-id: idea-id }
      {
        creator: tx-sender,
        idea-hash: idea-hash,
        title: title,
        timestamp: current-time,
        block-height: current-height,
        license-terms: license-terms,
        is-public: is-public,
        dispute-count: u0,
        latest-version: u1
      }
    )

    (map-set idea-versions
      { idea-id: idea-id, version: u1 }
      { hash: idea-hash, timestamp: current-time, changes: "" }
    )

    (map-set idea-ownership
      { creator: tx-sender, idea-hash: idea-hash }
      { idea-id: idea-id, timestamp: current-time }
    )

    (ok idea-id)
  )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (nft-transfer? mindchain-ip token-id sender recipient)
  )
)

(define-public (update-license-terms (idea-id uint) (new-terms (string-ascii 500)))
  (let
    (
      (idea (unwrap! (get-idea idea-id) ERR_NOT_FOUND))
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender token-owner) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (map-set ideas
      { idea-id: idea-id }
      (merge idea { license-terms: (some new-terms) })
    )
    (ok true)
  )
)

(define-public (toggle-idea-visibility (idea-id uint))
  (let
    (
      (idea (unwrap! (get-idea idea-id) ERR_NOT_FOUND))
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender token-owner) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (map-set ideas
      { idea-id: idea-id }
      (merge idea { is-public: (not (get is-public idea)) })
    )
    (ok (not (get is-public idea)))
  )
)

(define-public (create-dispute (idea-id uint) (evidence-hash (buff 32)))
  (let
    (
      (idea (unwrap! (get-idea idea-id) ERR_NOT_FOUND))
      (dispute-id (increment-dispute-id))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq tx-sender (get creator idea))) ERR_UNAUTHORIZED)
    (asserts! (is-eq (len evidence-hash) u32) ERR_INVALID_PARAMETERS)

    (map-set disputes
      { dispute-id: dispute-id }
      {
        idea-id: idea-id,
        challenger: tx-sender,
        evidence-hash: evidence-hash,
        status: "active",
        votes-for: u0,
        votes-against: u0,
        created-at: stacks-block-height,
        resolved-at: none
      }
    )

    (map-set ideas
      { idea-id: idea-id }
      (merge idea { dispute-count: (+ (get dispute-count idea) u1) })
    )

    (ok dispute-id)
  )
)

(define-public (vote-on-dispute (dispute-id uint) (vote-for bool))
  (let
    (
      (dispute (unwrap! (get-dispute dispute-id) ERR_NOT_FOUND))
      (voter-rep (get-voter-reputation tx-sender))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "active") ERR_NOT_DISPUTABLE)
    (asserts! (not (has-voted dispute-id tx-sender)) ERR_ALREADY_EXISTS)

    (map-set dispute-votes
      { dispute-id: dispute-id, voter: tx-sender }
      { vote: vote-for, timestamp: stacks-block-height }
    )

    (map-set voter-reputation
      { voter: tx-sender }
      {
        reputation: (get reputation voter-rep),
        total-votes: (+ (get total-votes voter-rep) u1)
      }
    )

    (if vote-for
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute { votes-for: (+ (get votes-for dispute) u1) })
      )
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute { votes-against: (+ (get votes-against dispute) u1) })
      )
    )
    (ok true)
  )
)

(define-public (resolve-dispute (dispute-id uint))
  (let
    (
      (dispute (unwrap! (get-dispute dispute-id) ERR_NOT_FOUND))
      (votes-for (get votes-for dispute))
      (votes-against (get votes-against dispute))
      (total-votes (+ votes-for votes-against))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "active") ERR_NOT_DISPUTABLE)
    (asserts! (>= total-votes u5) ERR_INVALID_PARAMETERS)

    (let
      (
        (resolved-status (if (> votes-for votes-against) "upheld" "rejected"))
      )
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute {
          status: resolved-status,
          resolved-at: (some stacks-block-height)
        })
      )
      (ok resolved-status)
    )
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (setup-royalty-agreement (idea-id uint) (royalty-rate uint))
  (let
    (
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender token-owner) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (validate-royalty-rate royalty-rate) ERR_INVALID_ROYALTY)
    (asserts!
      (is-none (get-royalty-agreement idea-id))
      ERR_ALREADY_EXISTS
    )

    (map-set royalty-agreements
      { idea-id: idea-id }
      {
        royalty-rate: royalty-rate,
        total-earned: u0,
        total-withdrawn: u0,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (pay-royalty (idea-id uint) (amount uint))
  (let
    (
      (agreement (unwrap! (get-royalty-agreement idea-id) ERR_NOT_FOUND))
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
      (royalty-amount (/ (* amount (get royalty-rate agreement)) u10000))
      (current-earnings (get-user-earnings token-owner idea-id))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (get active agreement) ERR_INVALID_PARAMETERS)
    (asserts! (> amount u0) ERR_INVALID_PARAMETERS)

    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (map-set royalty-agreements
      { idea-id: idea-id }
      (merge agreement { total-earned: (+ (get total-earned agreement) royalty-amount) })
    )

    (map-set user-earnings
      { user: token-owner, idea-id: idea-id }
      {
        earned: (+ (get earned current-earnings) royalty-amount),
        withdrawn: (get withdrawn current-earnings)
      }
    )
    (ok royalty-amount)
  )
)

(define-public (withdraw-earnings (idea-id uint))
  (let
    (
      (available (get-available-earnings tx-sender idea-id))
      (current-earnings (get-user-earnings tx-sender idea-id))
      (agreement (unwrap! (get-royalty-agreement idea-id) ERR_NOT_FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (> available u0) ERR_NO_EARNINGS)

    (try! (as-contract (stx-transfer? available tx-sender tx-sender)))

    (map-set user-earnings
      { user: tx-sender, idea-id: idea-id }
      {
        earned: (get earned current-earnings),
        withdrawn: (+ (get withdrawn current-earnings) available)
      }
    )

    (map-set royalty-agreements
      { idea-id: idea-id }
      (merge agreement { total-withdrawn: (+ (get total-withdrawn agreement) available) })
    )
    (ok available)
  )
)

(define-public (toggle-royalty-status (idea-id uint))
  (let
    (
      (agreement (unwrap! (get-royalty-agreement idea-id) ERR_NOT_FOUND))
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender token-owner) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (map-set royalty-agreements
      { idea-id: idea-id }
      (merge agreement { active: (not (get active agreement)) })
    )
    (ok (not (get active agreement)))
  )
)

(define-public (submit-idea-version (idea-id uint) (new-hash (buff 32)) (changes (string-ascii 200)))
  (let
    (
      (idea (unwrap! (get-idea idea-id) ERR_NOT_FOUND))
      (token-owner (unwrap! (nft-get-owner? mindchain-ip idea-id) ERR_NOT_FOUND))
      (current-version (get latest-version idea))
      (new-version (+ current-version u1))
    )
    (asserts! (is-eq tx-sender token-owner) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (validate-version-params changes new-hash) ERR_INVALID_PARAMETERS)
    (map-set idea-versions
      { idea-id: idea-id, version: new-version }
      { hash: new-hash, timestamp: stacks-block-height, changes: changes }
    )
    (map-set ideas
      { idea-id: idea-id }
      (merge idea { idea-hash: new-hash, latest-version: new-version })
    )
    (ok new-version)
  )
)
