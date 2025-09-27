# AURORA-Π (Pi) — Reversible Microcoded Cipher (RMC)

Spec sheet · draft 0.13 (CT engine, SHAKE-based derivation)

---

## 1) One‑page overview

- Type: tweakable, table‑free, constant‑time block cipher
- Block: 256 bits (4×64) · Key: 256 bits · Tweak: 128 bits (optional)
- Design novelty: each (key, tweak) instantiates a reversible “micro‑program” built from a tiny invertible ISA. There is no fixed S‑box/linear layer/rotation schedule; the per‑instance topology is KDF‑programmed.
- ISA: XOR lane,c · ADD lane,c(odd) · MUL lane,c(odd mod 2^64) · ROTL lane,r(1..63) · PERM π(32‑byte Fisher–Yates) · CROSS r1..r4 (cross‑lane ARX mixer).
- Steps (default): 64 micro‑ops (configurable by profile).
- Derivation: SHAKE256 XOF with domain separation derives whitening and the micro‑program (two streams: PROG|A then PROG|B at mid‑synthesis). Fisher–Yates uses rejection sampling (no modulo bias).
- Constant‑time engine: branchless, mask‑select executor. Every step evaluates all op candidates and selects via bit‑masks; byte permutation uses a constant‑time scatter‑gather; no secret‑dependent branches or indexing.

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

Given (K, T):

1) Derivation via SHAKE256 (XOF)
- Construct domain‑separated SHAKE256 contexts: WIN_PI, WOUT_PI, and PROG_PI|A and PROG_PI|B.
- Draw wIn and wOut (256 bits each) from WIN/WOUT.

2) Program synthesis (64 steps)
- For each step, sample an instruction from PROG (A for first half, then B).
- Strengthened quotas:
  - In every 8‑step window: at least one PERM and at least one CROSS; at least three total among {PERM,CROSS}; at least one MUL.
  - CROSS occurs at least once in each half of the window (steps 1–4 and 5–8).
  - Per‑lane MUL coverage: each lane is hit by MUL at least once in every 16‑step super‑window.
- Fisher–Yates for 32‑byte PERM uses rejection sampling (unbiased).

3) Inverse program
- Build dec as the exact inverse in reverse order: XOR self‑inverse; ADD ↔ SUB; MUL ↔ MUL(invOdd64(c)); ROTL r ↔ ROTR r; PERM π ↔ π⁻¹; CROSS has a fixed inverse sequence.

*Effect:* Topology and constants vary per (key, tweak) via domain‑separated XOF derivation, with regular, enforced diffusion/nonlinearity guarantees.

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

- Wide‑block horizon: 256‑bit block ⇒ ~2¹²⁸ birthday/data bound.
- True tweakability: tweak changes program topology and whitening (not just masks).
- Trail hostility: frequent PERM (byte diffusion), CROSS (lane coupling), and MUL (multiplicative nonlinearity) in every 8‑step window; 64 steps provide margin.
- Structural unpredictability: no fixed S‑box/MDS; per‑instance circuits frustrate global trails and templating.
- KDF robustness: SHAKE256 XOF with explicit domain separation derives whitening and the program. No reliance on a novel PRF.
- Constant‑time: branchless, mask‑select engine; constant‑time permutation; no secret‑dependent branches or table lookups.
- Related‑tweak hygiene: domain separation for derivations; tweak affects whitening and topology.
- PQ: 256‑bit key (~2¹²⁸ with Grover); 256‑bit block avoids small‑data quantum distinguishers.
---

## 7) Constants

No fixed round constants are used in the CT variant. All per‑instance material (whitening, instruction stream, permutations) is derived from SHAKE256 with domain separation.

---

## 8) Parameter choices & agility

- Max profile (default): Steps=64, window size 8 (PERM/CROSS/MUL quotas), mid‑synthesis switch A→B stream.
- Balanced profile: Steps=48 (same quotas/policy).
- Test profile: Steps≥32 (not for prod).

Build‑time flags: `-d:piProfile=max|balanced|test`.

---

## 9) Interop & versioning

- Algorithm ID (max), suggestion:
  `"AURORA-PI-RMC-256/256/128-S64-CT-SHAKE-S2V-v0.13"`
  (block/key/tweak/steps · CT engine · derivation/MAC · spec ver).
- Any change to ISA, engine, step count, or domain schedule bumps the ID.

---

## Appendix A — KAT guidance

1. Publish (K, T, PT → CT) vectors.
2. Include the **first 8 synthesized instructions** (audit only; not required for decryption).
3. Publish a profile hash over: `AlgID || SHAKE DS tags || rotation sets || quota policy || domain schedule`.
4. Provide KATs for all profiles (max/balanced/test) to prevent parameter drift.

---

## Appendix B — Delta 0.12 → 0.13

- New constant‑time engine: branchless, mask‑select per step; always executes all op candidates; constant‑time permutation.
- Derivation switch: replaced custom AURX512 PRF with SHAKE256 XOF for whitening and program synthesis (domain‑separated; unbiased permutation).
- Deterministic AEAD: π‑SIV now implemented via S2V with HMAC‑SHA3‑256 (trunc128) + CTR; MAC key derived via SHAKE256 (no PRP dependency).
- Profiles retained (Steps=64 default; 48 balanced; 32 test).
- Quota policy strengthened: ≥1 PERM and ≥1 CROSS per 8‑step window; ≥3 total among {PERM,CROSS}; ≥2 CROSS per window (one per half); ≥1 MUL per window and per‑lane MUL at least once per 16 steps.
- Algorithm ID bumped accordingly.
## 2a) Public API (easy to use)

For application developers, use `aurora.nim` which wraps common modes with clear checks and names:

Example (Nim):

```
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
var sector = newSeq[byte](64) # 2 blocks
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
- Keys are 32 bytes; tweak is optional 16 bytes. API throws `AuroraError` on invalid inputs.
- CTR requires a unique 16‑byte nonce per key.
- XEX (tweakable) supports block‑aligned data; use AE variants for authenticity.
- AEAD modes:
  - `xexSeal/xexOpen`: π‑XEX‑AE (keyed‑delta XEX with integrated tag). Block‑aligned, authenticates AD+tweak+ciphertext.
  - `sivSeal/sivOpen`: π‑SIV via S2V(HMAC‑SHA3‑256) + CTR. Deterministic, misuse‑resistant; safe default.

---

## KATs (Known Answer Tests)

Generate and lock deterministic vectors for each build profile.

Build and run
- Max profile (default):
  - `mkdir -p kats`
  - `nim c --path:src -d:release -d:piProfile=max kats/kat_gen.nim && ./kats/kat_gen > kats/aurora-pi-kat-max.txt`
- Balanced profile:
  - `nim c --path:src -d:release -d:piProfile=balanced kats/kat_gen.nim && ./kats/kat_gen > kats/aurora-pi-kat-balanced.txt`
- Test profile:
  - `nim c --path:src -d:release -d:piProfile=test kats/kat_gen.nim && ./kats/kat_gen > kats/aurora-pi-kat-test.txt`

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
  - `nim c --path:src -d:release -d:piProfile=max kats/kat_gen.nim && ./kats/kat_gen > out.txt && diff -u kats/aurora-pi-kat-max.txt out.txt`

Regenerating on intentional changes
- If you change parameters (e.g., PRF rounds, quotas, constants), regenerate all three files and commit them with a note explaining the change.
- CI enforces this by rebuilding KATs and diffing against files in `kats/` (see `.github/workflows/kats.yml`).

Notes
- PROGRAM_FIRST8 is provided for auditing and interop debugging.
- Hex is uppercase; ASCII inputs (like CTR_MSG) are hex-encoded for consistency.
