# AURORA-Π (Pi) — Reversible Microcoded Cipher (RMC)

**Spec sheet · draft 0.12 (max profile default)**

---

## 1) One‑page overview

* **Type:** tweakable, table‑free, constant‑time block cipher
* **Block:** 256 bits (4×64) · **Key:** 256 bits · **Tweak:** 128 bits (optional)
* **Design novelty:** each (key, tweak) instantiates a **reversible micro‑program** built from a tiny **invertible ISA**. There is no fixed S‑box/linear layer/rotation schedule; the per‑instance round *topology* is PRF‑programmed.
* **ISA:** `XOR lane,c`, `ADD lane,c(odd)`, `MUL lane,c(odd mod 2^64)`, `ROTL lane,r(1..63)`, `PERM π(32‑byte Fisher–Yates)`, `CROSS r1..r4` (cross‑lane ARX mixer).
* **Steps (default):** **64** micro‑ops (configurable by profile).
* **PRF:** **AURX512** — a 512‑bit ARX+MUL permutation used as a sponge/PRF with **transparent constants**, **per‑round odd multipliers derived from (key,tweak)**, **keyed nonlinear counter absorption**, **domain separation**, **capacity bump**, and **mid‑synthesis re‑absorb**.
* **Side‑channel:** constant‑time (no tables, no secret branches).

---

## 2) Interfaces

```
BlockSize  = 256 bits (32 bytes)
KeySize    = 256 bits (32 bytes)
TweakSize  = 128 bits (16 bytes, may be empty)
Steps      = 64   // max profile default
```

Library provides `expandKey`, `encryptBlock`, `decryptBlock`, stream/XEX modes, and AEAD (π-XEX-AE, π-SIV).

---

## 3) State & notation

* Internal state **S** is 256‑bit as **four 64‑bit lanes** `S[0..3]`.
* Little‑endian loads/stores; 64‑bit arithmetic is mod `2^64`.
* `ROTL`/`ROTR` are word rotates; `π` permutes bytes 0..31 invertibly.

---

## 4) Key schedule & code generation

Given `(K,T)`:

1. **AURX512 PRF init (sponge).**

   * State: 8×u64 (512‑bit) with 64‑bit counter.
   * Core permutation `aurxPerm`: **28 rounds** of ARX+MUL with cross‑lane coupling, lane shuffles, and constant coverage of all lanes each round. Two **mix flavors** (`mix`/`mix2`) alternate per round with distinct rotation sets.
   * **Per‑round odd multipliers** are derived from (K,T) (transparent method below).
   * Initialization absorbs key/tweak and runs **12 warm‑up permutations**.

2. **Domain‑separated draws.**

   * Absorb a 64‑bit domain tag before each phase: `DOM_WIN`, `DOM_WOUT`, `DOM_PROG`.
   * Draw **wIn** and **wOut** (256 bits each) from the PRF after `DOM_WIN`/`DOM_WOUT`.

3. **Program synthesis (64 steps).**

   * For each step, sample an instruction from the ISA via the PRF (`next64()`).
   * **Per‑window quotas:** in every **8‑step** window, enforce at least one `PERM`, one `CROSS`, and one `MUL` (enforced only if the window would otherwise miss them).
   * **Mid‑synthesis re‑absorb:** at half the program, absorb an extra tag (`DOM_PROG, 0x04`) to “rekey” the code stream.

4. **Inverse program.**

   * Build `dec` as the exact inverse in reverse order: `XOR` self‑inverse; `ADD` ↔ `SUB`; `MUL` ↔ `MUL(invOdd64(c))`; `ROTL r` ↔ `ROTR r`; `PERM π` ↔ `PERM π⁻¹`; `CROSS` has a fixed inverse sequence.

*Effect:* Topology and constants vary per (key, tweak) with **nonlinear PRF evolution**, domain separation, and regular diffusion/nonlinearity guarantees.

---

## 5) Algorithms

**Encrypt**

```
S = load(pt)
S ^= wIn
for I in enc: S = Exec(I, S)
S ^= wOut
ct = store(S)
```

**Decrypt**

```
S = load(ct)
S ^= wOut
for I in dec: S = ExecInverse(I, S)
S ^= wIn
pt = store(S)
```

---

## 6) Security goals & claims

* **Wide‑block horizon:** 256‑bit block ⇒ \~2¹²⁸‑block birthday/data bound.
* **True tweakability:** tweak changes **program topology** and whitening (not just masks).
* **Trail hostility:** frequent `PERM` (byte diffusion), `CROSS` (lane coupling), and `MUL` (multiplicative nonlinearity) in every 8‑step window; **64 steps** provide generous margin.
* **Structural unpredictability:** no fixed S‑box/MDS; per‑instance circuits frustrate global differential/linear trails and algebraic templating.
* **PRF robustness:** AURX512 is **nonlinear inside the update** (adds & odd multipliers), alternates **two mix flavors**, absorbs a **keyed nonlinear counter** each refill, and uses **per‑round multipliers derived from (K,T)**; prevents linear‑core modeling and stream reuse.
* **Capacity bump:** PRF squeezes **2×u64** per refill (more hidden state).
* **Related‑tweak hygiene:** domain separation + tweak absorption ⇒ no simple cross‑phase/cross‑tweak relations.
* **PQ:** 256‑bit key (\~2¹²⁸ with Grover); 256‑bit block avoids small‑data quantum distinguishers.

*Heuristic claims pending public cryptanalysis; no proofs.*

---

## 7) Transparent constants (public derivation)

* Round‑constant families `RC_Ag` and `RC_Mg` are derived as follows:

  1. Seed values: `sa = FNV‑1a64("AURORA‑PI‑RC_A‑v1")`, `sm = FNV‑1a64("AURORA‑PI‑RC_M‑v1")`.
  2. Expand with **splitmix64**, 12 values each.
  3. Force multipliers **odd**: `RC_Mg[i] |= 1`.
* Per‑round odd multipliers `mulSched[28]` are derived from (K,T) via splitmix64 and forced odd.

---

## 8) Parameter choices & agility

* **Max profile (default):** `Steps=64`, `PermRounds=28`, `Warmup=12`, window size `8` with `PERM/CROSS/MUL` quotas, **mid‑synthesis absorb enabled**, **capacity squeeze=2 words**.
* **Balanced profile:** `Steps=48`, `PermRounds=20`, `Warmup=10`, quotas on, mid‑absorb on, capacity=2 words.
* **Test profile (not for prod):** `Steps≥32`, `PermRounds≥16`.

*Build‑time flags:* `-d:piProfile=max|balanced|test`.

---

## 9) Interop & versioning

* **Algorithm ID (max):**
  `"AURORA-PI-RMC-256/256/128-S64-P28-CAP2-DOMv2-v0.12"`
  (block/key/tweak/steps · PRF rounds · capacity setting · domain‑sep rev · spec ver).
* Any change to ISA, PRF rounds, step count, capacity, or domain schedule **bumps the ID**.

---

## Appendix A — KAT guidance

1. Publish (K, T, PT → CT) vectors.
2. Include the **first 8 synthesized instructions** (audit only; not required for decryption).
3. Publish a **PRF profile hash**, e.g. SHA‑256 over: `AlgID || constant seeds || rotation sets || quota policy || domain schedule`.
4. Provide KATs for all profiles (max/balanced/test) to prevent parameter drift.

---

## Appendix B — Delta 0.11 → 0.12

* Steps 48→**64** (default max).
* PRF upgraded to **AURX512** with **28** permutation rounds, **dual mix flavors**, lane‑wide constant coverage.
* **Keyed nonlinear counter absorption** at each refill.
* **Per‑round odd multipliers** derived from (K,T).
* **Transparent constant derivation** (FNV‑1a64 + splitmix64).
* **Capacity bump**: squeeze **2 words** per refill.
* **Mid‑synthesis re‑absorb** retained; per‑window quotas retained.
## 2a) Public API (easy to use)

For application developers, use `aurora.nim` which wraps common modes with clear checks and names:

Example (Nim):

```
import aurora/api

let key = @[byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31]
let tweak = @[byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]  # optional
let cipher = newAuroraPiContext(key, tweak)

# CTR mode (requires unique nonce per key)
let nonce = randomNonce16()
var msg = toBytes("Hello, world!")
let ct = cipher.ctrEncrypt(nonce, msg)
let pt = cipher.ctrDecrypt(nonce, ct)

# XEX mode (tweakable, length must be multiple of 32)
let sectorTweak = @[byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
var sector = newSeq[byte](64) # 2 blocks
let xct = cipher.xexEncrypt(sectorTweak, sector)
let xpt = cipher.xexDecrypt(sectorTweak, xct)

# π-XEX-AE (authenticated, block-aligned, tweakable)
let ad = toBytes("header-metadata")
let (ct2, tag) = cipher.xexSeal(sectorTweak, ad, sector)
let pt2 = cipher.xexOpen(sectorTweak, ad, ct2, tag)

# π-SIV (deterministic AEAD, misuse-resistant)
let msg2 = toBytes("secret")
let (siv, ct3) = cipher.sivSeal(@[], msg2)
let pt3 = cipher.sivOpen(@[], siv, ct3)
```

Notes:
- Keys are 32 bytes; tweak is optional 16 bytes. API throws `AuroraError` with helpful messages on invalid inputs.
- CTR requires a unique 16-byte nonce for each message under a given key; use `randomNonce16()` on POSIX or your own CSPRNG.
- XEX (tweakable) supports block-aligned data; use AE variants for authenticity.
- AEAD modes:
  - `xexSeal/xexOpen`: π-XEX-AE (keyed-delta XEX with integrated tag). Block-aligned, parallelizable, authenticates AD+tweak+ciphertext.
  - `sivSeal/sivOpen`: π-SIV (deterministic AEAD). Misuse-resistant; safe default for general use.

---

## KATs (Known Answer Tests)

Generate and lock deterministic vectors for each build profile.

Build and run
- Max profile (default):
  - `mkdir -p kats`
  - `nim c --path:src -d:release -d:piProfile=max tools/kat.nim && ./tools/kat > kats/aurora-pi-kat-max.txt`
- Balanced profile:
  - `nim c --path:src -d:release -d:piProfile=balanced tools/kat.nim && ./tools/kat > kats/aurora-pi-kat-balanced.txt`
- Test profile:
  - `nim c --path:src -d:release -d:piProfile=test tools/kat.nim && ./tools/kat > kats/aurora-pi-kat-test.txt`

What’s included in each file
- PROGRAM_FIRST8: the first eight synthesized instructions (audit-only; not required for decryption).
- Core block: K, T, PT_BLK, CT_BLK, DT_BLK.
- CTR: CTR_NONCE, CTR_MSG (ASCII), CTR_CT.
- XEX (conf-only): XEX_TWEAK, XEX_PT, XEX_CT.
- π-XEX-AE: XEXAE_AD, XEXAE_CT, XEXAE_TAG (32 bytes).
- π-SIV: SIV_AD, SIV_IV (16 bytes), SIV_CT.

Determinism & profiles
- Vectors are deterministic for a given profile (max/balanced/test). Changing `-d:piProfile` changes the synthesized program and outputs.
- Ensure you compile with `--path:src` so Nim can find modules under `src/`.

Verifying locally
- Rebuild and diff against committed vectors:
  - `nim c --path:src -d:release -d:piProfile=max tools/kat.nim && ./tools/kat > out.txt && diff -u kats/aurora-pi-kat-max.txt out.txt`

Regenerating on intentional changes
- If you change parameters (e.g., PRF rounds, quotas, constants), regenerate all three files and commit them with a note explaining the change.
- CI enforces this by rebuilding KATs and diffing against files in `kats/` (see `.github/workflows/kats.yml`).

Notes
- PROGRAM_FIRST8 is provided for auditing and interop debugging.
- Hex is uppercase; ASCII inputs (like CTR_MSG) are hex-encoded for consistency.
