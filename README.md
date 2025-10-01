# AURORA-Π (Pi) — Reversible Microcoded Cipher (RMC)

**Spec sheet · draft 0.14 (CT engine, SHAKE-based derivation)**

---

## 1) One-page overview

* **Type:** tweakable, table-free, constant-time block cipher
* **Block:** 256 bits (4×64) · **Key:** 256 bits · **Tweak:** 128 bits (optional)
* **Design idea:** each **key** instantiates a reversible “micro-program” built from a tiny invertible ISA. No fixed S-box/MDS/rotation schedule; the per-instance topology is KDF-programmed **from the key**. The **tweak** affects whitening (not the program topology).
* **ISA:** `XOR lane,c` · `ADD lane,c` (**c ≠ 0**) · `MUL lane,c` (**c odd, c ≠ 1 mod 2^64**) · `ROTL lane,r (1..63)` · `PERM π` (32-byte Fisher–Yates) · `CROSS r1..r4` (cross-lane ARX mixer).
* **Steps (default):** 64 micro-ops (configurable by profile).
* **Derivation:** SHAKE256 XOF with domain separation derives **whitening from (key,tweak)** and the **micro-program from key only** (two streams: `PROG|A` then `PROG|B` mid-synthesis).
* **Sampling:** range reduction is **rejection-free** via 128-bit multiply-high when available; fallback uses **unbiased rejection**. Fisher–Yates remains unbiased.
* **Constant-time engine:** branchless, mask-select executor. Every step evaluates all op candidates and selects via bit-masks; byte permutation uses a constant-time scatter-gather; no secret-dependent branches or indexing. Corrected equality masks; identity constants avoided via **branchless mapping** (no “retry” loops).

---

## 2) Interfaces

```
BlockSize  = 256 bits (32 bytes)
KeySize    = 256 bits (32 bytes)
TweakSize  = 128 bits (16 bytes, may be empty)
Steps      = 64   // max profile default
```

Library provides `expandKey`, `encryptBlock`, `decryptBlock`, stream/XEX modes, and AEAD (`π-XEX-AE`, `π-SIV`).

---

## 3) State & notation

* Internal state **S** is 256-bit as **four 64-bit lanes** `S[0..3]`.
* Little-endian loads/stores; 64-bit arithmetic is mod `2^64`.
* `ROTL`/`ROTR` are word rotates; `π` permutes bytes 0..31 invertibly.

---

## 4) Key schedule & code generation

Given `(K, T)`:

1. **Derivation via SHAKE256 (XOF)**
   Construct domain-separated contexts:

   * `WIN_PI`, `WOUT_PI` **depend on (key, tweak)** and produce 256-bit `wIn` and `wOut`.
   * `PROG_PI|A`, `PROG_PI|B` **depend on key only** and drive micro-program synthesis.

2. **Program synthesis (64 steps)**
   For each step, sample an instruction from `PROG` (`A` for first half, then `B`).
   **Strengthened quotas (per 8-step window):**

   * ≥1 `PERM` and ≥1 `CROSS`
   * ≥3 total among {`PERM`,`CROSS`}
   * ≥1 `MUL`
   * ≥1 of {`ADD`, `ROTL`}
   * `CROSS` occurs at least once in each half (steps 1–4 and 5–8).
     **Super-window (16 steps):** each lane gets a `MUL` at least once.
     **Sampling:** range reduction uses rejection-free 128-bit multiply-high when available; otherwise unbiased rejection. Fisher–Yates is unbiased.

3. **Inverse program**
   Build `dec` as the exact inverse in reverse order:
   `XOR` self-inverse; `ADD` ↔ `SUB`; `MUL` ↔ `MUL(invOdd64(c))`; `ROTL r` ↔ `ROTR r`; `PERM π` ↔ `π⁻¹`; `CROSS` uses its fixed inverse sequence.

*Effect:* topology and constants vary **per key**; the **tweak** influences whitening (not topology), with enforced diffusion/nonlinearity guarantees.

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

* **Wide-block horizon:** 256-bit block ⇒ ~2¹²⁸ birthday/data bound.
* **True tweakability:** tweak changes **whitening** (not program topology).
* **Trail hostility:** frequent `PERM` (byte diffusion), `CROSS` (lane coupling), `MUL` (multiplicative nonlinearity) in every window; 64 steps provide margin.
* **Structural unpredictability:** no fixed S-box/MDS; per-instance circuits frustrate global trails and templating.
* **KDF robustness:** SHAKE256 XOF with explicit domain separation derives whitening and program as specified above.
* **Constant-time:** branchless mask-select engine; constant-time permutation; **corrected equality masks**; identity constants avoided via **branchless mapping**. (Key setup uses rejection-free range reduction when `uint128` is available; fallback is unbiased rejection.)
* **PQ:** 256-bit key (~2¹²⁸ with Grover); 256-bit block avoids small-data quantum distinguishers.

---

## 7) Constants

No fixed round constants are used in the CT variant. All per-instance material (whitening, instruction stream, permutations) is derived from SHAKE256 with domain separation.

---

## 8) Parameter choices & agility

* **Max profile (default):** `Steps=64`, window size 8, quotas above, mid-synthesis `A→B`.
* **Balanced profile:** `Steps=48` (same quotas/policy).
* **Test profile:** `Steps≥32` (not for production).

Build-time flag: `-d:piProfile=max|balanced|test`.

---

## 9) Interop & versioning

* **Algorithm ID (suggested):**
  `"AURORA-PI-RMC-256/256/128-S64-CT-SHAKE-S2V-v0.14"`
  (block/key/tweak/steps · CT engine · derivation/MAC · spec ver)
* Any change to ISA, engine, step count, or domain schedule bumps the ID.
  (Drop “-S2V” if this repo doesn’t ship SIV.)

---

## Appendix A — KAT guidance

1. Publish `(K, T, PT → CT)` vectors.
2. Include the **first 8 synthesized instructions** (audit only; not required for decryption).
3. Publish a profile hash over: `AlgID || SHAKE DS tags || rotation sets || quota policy || domain schedule`.
4. Provide KATs for all profiles (max/balanced/test) to prevent parameter drift.

**Build & run (examples)**

* Max profile (default):

  ```
  nim c --path:src -d:release -d:piProfile=max kats/kat_gen.nim
  ./kats/kat_gen > kats/aurora-pi-kat-max.txt
  ```
* Balanced profile:

  ```
  nim c --path:src -d:release -d:piProfile=balanced kats/kat_gen.nim
  ./kats/kat_gen > kats/aurora-pi-kat-balanced.txt
  ```
* Test profile:

  ```
  nim c --path:src -d:release -d:piProfile=test kats/kat_gen.nim
  ./kats/kat_gen > kats/aurora-pi-kat-test.txt
  ```

Each file includes:

* `PROGRAM_FIRST8` (audit)
* Core block: `K, T, PT_BLK, CT_BLK, DT_BLK`
* CTR: `CTR_NONCE, CTR_MSG (ASCII as hex), CTR_CT`
* XEX (conf-only): `XEX_TWEAK, XEX_PT, XEX_CT`
* **π-XEX-AE:** `XEXAE_AD, XEXAE_CT, XEXAE_TAG (32 bytes)`
* **π-SIV:** `SIV_AD, SIV_IV (16 bytes), SIV_CT`

**Verify locally**

```
nim c --path:src -d:release -d:piProfile=max kats/kat_gen.nim
./kats/kat_gen > out.txt
diff -u kats/aurora-pi-kat-max.txt out.txt
```

Regenerate on intentional changes (parameters/quotas/constants) and commit with notes; CI should rebuild KATs and diff against `kats/`.

---

## Appendix B — Delta 0.13 → 0.14

* **Correctness/CT:** fixed 32/64-bit equality masks; lane masks for non-lane ops are cleanly zeroed without branching.
* **CT hardening:** removed identity retries by **branchless** mapping of constants

  * `XOR:` `c ≠ 0`
  * `ADD:` `c ≠ 0` (was “odd”)
  * `MUL:` `c` odd, `c ≠ 1` (same semantics; now mapped without loops)
* **Quotas:** added **≥1 of {ADD, ROTL}** per 8-step window.
* **Sampling:** range reduction is **rejection-free** via 128-bit multiply-high when available; fallback remains unbiased rejection.
* **Hygiene:** optional `wipeKeySchedule` helper for zeroization.
* **Alg ID:** bumped to **v0.14**.

---

## 2a) Public API (easy to use)

For application developers, use `aurora.nim` which wraps common modes with checks:

```nim
import aurora

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
var sector = newSeq # 2 blocks
let xct = cipher.xexEncrypt(sectorTweak, sector)
let xpt = cipher.xexDecrypt(sectorTweak, xct)

# π-XEX-AE (authenticated, block-aligned, tweakable)
let ad = toBytes("header-metadata")
let (ct2, tag) = cipher.xexSeal(sectorTweak, ad, sector)
let pt2 = cipher.xexOpen(sectorTweak, ad, ct2, tag)

# π-SIV (S2V; deterministic AEAD, misuse-resistant)
let msg2 = toBytes("secret")
let (siv, ct3) = cipher.sivSeal(@[], msg2)
let pt3 = cipher.sivOpen(@[], siv, ct3)
```

Notes:

* Keys are 32 bytes; tweak is optional 16 bytes. API throws `AuroraError` on invalid inputs.
* CTR requires a unique 16-byte nonce per key.
* XEX (tweakable) supports block-aligned data; use AE variants for authenticity.
* AEAD modes:

  * `xexSeal/xexOpen`: π-XEX-AE (keyed-delta XEX with tag).
  * `sivSeal/sivOpen`: π-SIV via S2V(HMAC-SHA3-256) + CTR. Deterministic, misuse-resistant.
