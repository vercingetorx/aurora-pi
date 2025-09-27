# ========================================
# File: tools/kat.nim
# KAT generator for Aurora-Π core and modes
# Build:
#   nim c -d:release -d:piProfile=max kats/kat_gen.nim   # or balanced/test
# Run:
#   ./kats/kat_gen
# ========================================
import std/[sequtils, strutils, strformat]
import ../src/hexutil
import ../src/aurora256
import ../src/common
import ../aurora


when isMainModule:
  let key = incBytes(32)
  let tweak = incBytes(16)
  let cipher = newAuroraPiContext(key, tweak)

  printLine()
  echo "Aurora-Π KATs"
  printLine()

  # Algorithm ID (reflects CT engine and derivations)
  let ks = cipher.keySchedule
  let steps = ks.enc.len
  let algId = fmt"AURORA-PI-RMC-256/256/128-S{steps}-CT-SHAKE-S2V-v0.13"
  printKV("ALG_ID", algId)

  # Program audit: first 8 instructions
  let prog8 = describeFirstInstrs(ks, 8)
  echo "PROGRAM_FIRST8:\n", prog8

  # Block KAT
  let ptBlk = incBytes(32)
  let ctBlk = cipher.encryptBlock(ptBlk)
  let dtBlk = cipher.decryptBlock(ctBlk)
  printKV("K", toHex(key))
  printKV("T", toHex(tweak))
  printKV("PT_BLK", toHex(ptBlk))
  printKV("CT_BLK", toHex(ctBlk))
  printKV("DT_BLK", toHex(dtBlk))

  printLine()
  # CTR KAT
  let nonce = incBytes(16)
  let msg = toBytes("The quick brown fox jumps over 13 lazy dogs.")
  let ctStream = cipher.ctrEncrypt(nonce, msg)
  printKV("CTR_NONCE", toHex(nonce))
  printKV("CTR_MSG", toHex(msg))
  printKV("CTR_CT", toHex(ctStream))

  printLine()
  # XEX KAT (conf-only)
  let sectorTweak = bytesSeq([0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff])
  var sector = incBytes(64)
  let xct = cipher.xexEncrypt(sectorTweak, sector)
  printKV("XEX_TWEAK", toHex(sectorTweak))
  printKV("XEX_PT", toHex(sector))
  printKV("XEX_CT", toHex(xct))

  printLine()
  # π-XEX-AE KAT
  let ad = toBytes("AD")
  let (ct2, tag) = cipher.xexSeal(sectorTweak, ad, sector)
  printKV("XEXAE_AD", toHex(ad))
  printKV("XEXAE_CT", toHex(ct2))
  printKV("XEXAE_TAG", toHex(tag))

  printLine()
  # π-SIV KAT (deterministic AEAD)
  let msg2 = toBytes("secret message")
  let (siv, ct3) = cipher.sivSeal(ad, msg2)
  printKV("SIV_AD", toHex(ad))
  printKV("SIV_IV", toHex(siv))
  printKV("SIV_CT", toHex(ct3))
  printLine()
