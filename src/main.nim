# AURORA-Π (Aurora-Pi)
# Next‑gen tweakable block cipher & modes
# -----------------------------------------------------------
# Project layout (multiple files in one canvas):
#   src/aurora/common.nim
#   src/aurora/aurora256.nim
#   src/aurora/modes.nim
#   src/aurora/hexutil.nim
#   src/aurora/fileops.nim
#   src/main.nim
#
# Compile:
#   nim c -d:release src/main.nim
#
# -----------------------------------------------------------

# ========================================
# File: src/main.nim
# ========================================
import std/os
import aurora/hexutil
import aurora/aurora256
import aurora/modes
import aurora/fileops

proc demo() =
  echo "AURORA-Λ demo\n----------------"
  let keyHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  let tweakHex = "000102030405060708090a0b0c0d0e0f"
  var key = parseHex(keyHex)
  var tweak = parseHex(tweakHex)
  let ks = expandKey(key, tweak)

  # Encrypt/Decrypt one block
  var blkHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  var blk = parseHex(blkHex)

  let ct = ks.encryptBlock(blk)
  let pt = ks.decryptBlock(ct)

  echo "PT: ", toHex(blk)
  echo "CT: ", toHex(ct)
  echo "DT: ", toHex(pt)

  # CTR demo
  var nonce = parseHex("00000000000000000000000000000000")
  var cs = initCtr(ks, nonce)
  let s = "Hello, world! — AURORA-Λ"
  var msg = newSeq[byte](s.len)
  for i in 0..<s.len: msg[i] = byte(s[i])
  cs.ctrXor(msg)
  echo "CTR CT: ", toHex(msg)
  cs = initCtr(ks, nonce) # reset to decrypt
  cs.ctrXor(msg)
  var outp = newString(msg.len)
  for i in 0..<msg.len: outp[i] = char(msg[i])
  echo "CTR PT: ", outp

  # XEX demo (two blocks)
  var sectorTweak = parseHex("00112233445566778899aabbccddeeff")
  var big = newSeq[byte](64)
  for i in 0..<64: big[i] = byte(i)
  let xct = xexEncrypt(ks, sectorTweak, big)
  let xpt = xexDecrypt(ks, sectorTweak, xct)
  echo "XEX CT (64B): ", toHex(xct)
  echo "XEX OK? ", $(xpt == big)

proc fileDemo(
  plainPath: string = "demo_plain.png",
  cipherPath: string = "demo_cipher.bin",
  recoverPath: string = "demo_recover.png"
) =
  # File CTR demo
  let keyHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  let tweakHex = "000102030405060708090a0b0c0d0e0f"
  let nonceHex = "00112233445566778899aabbccddeeff"

  if not fileExists(plainPath):
    var f: File
    if not f.open(plainPath, fmWrite):
      raise newException(IOError, "cannot create demo file: " & plainPath)
    var buffer = newSeq[byte](1024)
    for i in 0..<buffer.len: buffer[i] = byte(i and 0xff)
    discard f.writeBuffer(addr buffer[0], buffer.len)
    f.close()

  # Encrypt → Decrypt
  encryptFileCTR(plainPath, cipherPath, keyHex, tweakHex, nonceHex)
  decryptFileCTR(cipherPath, recoverPath, keyHex, tweakHex, nonceHex)

  # Verify round-trip
  let okfile = readFile(plainPath) == readFile(recoverPath)
  echo "File CTR OK? ", $okfile


when isMainModule:
  demo()
  # fileDemo()
