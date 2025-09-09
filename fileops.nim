# ========================================
# File: src/aurora/fileops.nim
# ========================================
when isMainModule: discard

import ./hexutil
import ./aurora256
import ./modes

const CHUNK* = 64 * 1024

proc ctrFileXor*(inPath, outPath, keyHex, tweakHex, nonceHex: string) =
  ## Encrypt/Decrypt a file using CTR. Same function for both directions.
  ## keyHex = 64 hex chars (32 bytes)
  ## tweakHex = 0 or 32 hex chars (0 or 16 bytes)
  ## nonceHex = 32 hex chars (16 bytes)
  let key = parseHex(keyHex)
  let tweak = if tweakHex.len == 0: @[] else: parseHex(tweakHex)
  let nonceSeq = parseHex(nonceHex)
  doAssert nonceSeq.len == 16, "nonce must be 16 bytes (32 hex)"
  var nonce: array[16, byte]
  for i in 0..15: nonce[i] = nonceSeq[i]

  let ks = expandKey(key, tweak)
  var cs = initCtr(ks, nonce)

  var fin, fout: File
  if not fin.open(inPath, fmRead):
    raise newException(IOError, "cannot open input: " & inPath)
  if not fout.open(outPath, fmWrite):
    fin.close(); raise newException(IOError, "cannot open output: " & outPath)

  var buf: array[CHUNK, byte]
  while true:
    let n = fin.readBuffer(addr buf[0], CHUNK)
    if n <= 0: break
    cs.ctrXor(buf.toOpenArray(0, n-1))
    discard fout.writeBuffer(addr buf[0], n)

  fin.close(); fout.close()

proc encryptFileCTR*(inPath, outPath, keyHex, tweakHex, nonceHex: string) =
  ctrFileXor(inPath, outPath, keyHex, tweakHex, nonceHex)

proc decryptFileCTR*(inPath, outPath, keyHex, tweakHex, nonceHex: string) =
  ctrFileXor(inPath, outPath, keyHex, tweakHex, nonceHex)
