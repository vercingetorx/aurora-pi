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

## 2) Interfaces (API unchanged)

```
BlockSize  = 256 bits (32 bytes)
KeySize    = 256 bits (32 bytes)
TweakSize  = 128 bits (16 bytes, may be empty)
Steps      = 64   // max profile default
```

Library provides `expandKey`, `encryptBlock`, `decryptBlock`, and stream/XEX/SIV modes.

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

## 5) Algorithms (unchanged)

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
* (Legacy fixed tables may appear in reference code but are **superseded** by the transparent generation above.)

---

## 8) Parameter choices & agility

* **Max profile (default):** `Steps=64`, `PermRounds=28`, `Warmup=12`, window size `8` with `PERM/CROSS/MUL` quotas, **mid‑synthesis absorb enabled**, **capacity squeeze=2 words**.
* **Balanced profile:** `Steps=48`, `PermRounds=20`, `Warmup=10`, quotas on, mid‑absorb on, capacity=2 words.
* **Test profile (not for prod):** `Steps≥32`, `PermRounds≥16`.

*Build‑time flag suggestion:* `-d:piProfile=max|balanced|test`.

---

## 9) Interop & versioning

* **Algorithm ID (max):**
  `"AURORA-PI-RMC-256/256/128-S64-P28-CAP2-DOMv2-v0.12"`
  (block/key/tweak/steps · PRF rounds · capacity setting · domain‑sep rev · spec ver).
* Any change to ISA, PRF rounds, step count, capacity, or domain schedule **bumps the ID**.

---

## Appendix A — Delta 0.11 → 0.12 (for reviewers)

* Steps 48→**64** (default max).
* PRF upgraded to **AURX512** with **28** permutation rounds, **dual mix flavors**, lane‑wide constant coverage.
* **Keyed nonlinear counter absorption** at each refill.
* **Per‑round odd multipliers** derived from (K,T).
* **Transparent constant derivation** (FNV‑1a64 + splitmix64).
* **Capacity bump**: squeeze **2 words** per refill.
* **Mid‑synthesis re‑absorb** retained; per‑window quotas retained.
