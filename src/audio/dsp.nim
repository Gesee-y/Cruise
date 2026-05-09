##########################################################################################################################################################
################################################################# DSP COMMON #############################################################################
##########################################################################################################################################################


##########################################################################################################################################################
## INTERNAL HELPERS
##########################################################################################################################################################

template checkCompat*[B, T](a, b: CSampledBuf[B, T], op: string) =
  ## Assert that `a` and `b` are compatible for a binary DSP operation.
  assert a.nchannels  == b.nchannels,  op & ": channel count mismatch"
  assert a.nframes    == b.nframes,    op & ": frame count mismatch"
  assert a.sampleRate == b.sampleRate, op & ": sample rate mismatch"

##########################################################################################################################################################
## GAIN
##########################################################################################################################################################

proc gain*[B, T](buf: CSampledBuf[B, T], factor: T): CSampledBuf[B, T] =
  ## Return a new buffer with every sample multiplied by `factor`.
  CSampledBuf[B, T](
    data:       buf.data * factor,
    nframes:    buf.nframes,
    nchannels:  buf.nchannels,
    sampleRate: buf.sampleRate
  )

proc gainInto*[B, T](buf: CSampledBuf[B, T], factor: T, dst: var CSampledBuf[B, T]) =
  ## Write `buf * factor` into `dst`.  Reuses `dst`'s backing memory when large enough.
  mulScalar(buf.data, factor, dst.data)
  dst.nframes    = buf.nframes
  dst.nchannels  = buf.nchannels
  dst.sampleRate = buf.sampleRate

proc gainIP*[B, T](buf: var CSampledBuf[B, T], factor: T) =
  ## In-place gain: multiply every sample by `factor`.
  buf.data *= factor

##########################################################################################################################################################
## MIX
##########################################################################################################################################################

proc mix*[B, T](a, b: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a new buffer that is the element-wise sum of `a` and `b`.
  checkCompat(a, b, "mix")
  CSampledBuf[B, T](
    data:       a.data + b.data,
    nframes:    a.nframes,
    nchannels:  a.nchannels,
    sampleRate: a.sampleRate
  )

proc mix*[B, T](a, b: CSampledBuf[B, T], levelA, levelB: T): CSampledBuf[B, T] =
  ## Return `a * levelA + b * levelB`.  Useful for wet/dry blending.
  checkCompat(a, b, "mix")
  CSampledBuf[B, T](
    data:       (a.data * levelA) + (b.data * levelB),
    nframes:    a.nframes,
    nchannels:  a.nchannels,
    sampleRate: a.sampleRate
  )

proc mixInto*[B, T](a, b: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write `a + b` into `dst`.
  checkCompat(a, b, "mixInto")
  add(a.data, b.data, dst.data)
  dst.nframes    = a.nframes
  dst.nchannels  = a.nchannels
  dst.sampleRate = a.sampleRate

proc mixInto*[B, T](a, b: CSampledBuf[B, T], levelA, levelB: T,
                                dst: var CSampledBuf[B, T]) =
  ## Write `a * levelA + b * levelB` into `dst`.
  checkCompat(a, b, "mixInto")
  dst.data       = (a.data * levelA) + (b.data * levelB)
  dst.nframes    = a.nframes
  dst.nchannels  = a.nchannels
  dst.sampleRate = a.sampleRate

proc mixIP*[B, T](a: var CSampledBuf[B, T], b: CSampledBuf[B, T]) =
  ## In-place mix: add `b` into `a`.
  checkCompat(a, b, "mixIP")
  a.data += b.data

proc mixIP*[B, T](a: var CSampledBuf[B, T], b: CSampledBuf[B, T],
                              levelA, levelB: T) =
  ## In-place mix with levels: `a = a * levelA + b * levelB`.
  checkCompat(a, b, "mixIP")
  a.data *= levelA
  a.data += b.data * levelB

##########################################################################################################################################################
## CLIP
##########################################################################################################################################################

proc clip*[B, T](buf: CSampledBuf[B, T], limit: T = T(1.0)): CSampledBuf[B, T] =
  ## Return a new buffer with samples clamped to `[-limit, +limit]`.
  ## Delegates to the backend's min/max element-wise ops.
  let pos =  limit
  let neg = -limit
  CSampledBuf[B, T](
    data:       buf.data.min(pos).max(neg),   # backend provides element-wise min/max
    nframes:    buf.nframes,
    nchannels:  buf.nchannels,
    sampleRate: buf.sampleRate
  )

proc clipInto*[B, T](buf: CSampledBuf[B, T], limit: T,
                                 dst: var CSampledBuf[B, T]) =
  ## Write clipped samples into `dst`.
  dst = buf.clip(limit)
  dst.nframes    = buf.nframes
  dst.nchannels  = buf.nchannels
  dst.sampleRate = buf.sampleRate

proc clipIP*[B, T](buf: var CSampledBuf[B, T], limit: T = T(1.0)) =
  ## In-place clip.
  buf = buf.clip(limit)

##########################################################################################################################################################
## NORMALIZE — peak
##########################################################################################################################################################

proc normalize*[B, T](buf: CSampledBuf[B, T],
                                  target: T = T(1.0)): CSampledBuf[B, T] =
  ## Return a new buffer scaled so the peak absolute value equals `target`.
  ## Returns `buf` unchanged when the signal is silent.
  let peak = abs(buf.data).max()
  if peak == T(0): return buf
  buf.gain(target / peak)

proc normalizeInto*[B, T](buf: CSampledBuf[B, T], target: T,
                                      dst: var CSampledBuf[B, T]) =
  ## Write peak-normalised samples into `dst`.
  dst = buf.normalize(target)

proc normalizeIP*[B, T](buf: var CSampledBuf[B, T], target: T = T(1.0)) =
  ## In-place peak normalise.
  let peak = abs(buf.data).max()
  if peak == T(0): return
  buf.gainIP(target / peak)

##########################################################################################################################################################
## NORMALIZE — RMS
##########################################################################################################################################################

proc rms*[B, T](buf: CSampledBuf[B, T]): T =
  ## Compute the Root Mean Square amplitude of `buf`.
  sqrt((buf.data * buf.data).sum() / T(buf.totalSamples))

proc normalizeRMS*[B, T](buf: CSampledBuf[B, T],
                                     target: T = T(0.25)): CSampledBuf[B, T] =
  ## Return a new buffer scaled so its RMS equals `target`.
  ## Default target is 0.25 (~-12 dBFS), a common broadcast level.
  let r = buf.rms()
  if r == T(0): return buf
  buf.gain(target / r)

proc normalizeRMSInto*[B, T](buf: CSampledBuf[B, T], target: T,
                                         dst: var CSampledBuf[B, T]) =
  ## Write RMS-normalised samples into `dst`.
  dst = buf.normalizeRMS(target)

proc normalizeRMSIP*[B, T](buf: var CSampledBuf[B, T],
                                       target: T = T(0.25)) =
  ## In-place RMS normalise.
  let r = buf.rms()
  if r == T(0): return
  buf.gainIP(target / r)

##########################################################################################################################################################
## FADE
##########################################################################################################################################################

proc applyRamp[B, T](buf: CSampledBuf[B, T],
                                 fadeIn: bool): CSampledBuf[B, T] =
  ## Internal: build a linear ramp seq on the backing type and multiply.
  ## The ramp runs 0→1 (fadeIn=true) or 1→0 (fadeIn=false) over nframes,
  ## repeated for every channel so interleaved layout is preserved.
  let n      = buf.totalSamples
  var ramp   = newSeq[T](n)
  let frames = buf.nframes.int
  let chans  = buf.nchannels.int
  for f in 0..<frames:
    let v = if fadeIn: T(f) / T(frames - 1)
            else:      T(1.0) - T(f) / T(frames - 1)
    for c in 0..<chans:
      ramp[f * chans + c] = v
  # Upload ramp to the same backend as buf, then multiply element-wise
  let rampBuf = ramp.toGPU()   # resolves to CLSeq or CPUSeq depending on B
  CSampledBuf[B, T](
    data:       buf.data * rampBuf,
    nframes:    buf.nframes,
    nchannels:  buf.nchannels,
    sampleRate: buf.sampleRate
  )

proc fadeIn*[B, T](buf: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a new buffer with a linear fade-in applied (silence → full level).
  applyRamp(buf, fadeIn = true)

proc fadeInInto*[B, T](buf: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write fade-in result into `dst`.
  dst = buf.fadeIn()

proc fadeInIP*[B, T](buf: var CSampledBuf[B, T]) =
  ## In-place fade-in.
  buf = buf.fadeIn()

proc fadeOut*[B, T](buf: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a new buffer with a linear fade-out applied (full level → silence).
  applyRamp(buf, fadeIn = false)

proc fadeOutInto*[B, T](buf: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write fade-out result into `dst`.
  dst = buf.fadeOut()

proc fadeOutIP*[B, T](buf: var CSampledBuf[B, T]) =
  ## In-place fade-out.
  buf = buf.fadeOut()

##########################################################################################################################################################
## REVERSE
##########################################################################################################################################################

proc reverse*[B, T](buf: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a new buffer with the frame order reversed (backwards playback).
  let frames = buf.nframes.int
  let chans  = buf.nchannels.int
  var rev    = newSeq[T](buf.totalSamples)
  # Build reversed layout on CPU then upload — backends handle the copy
  for f in 0..<frames:
    for c in 0..<chans:
      rev[f * chans + c] = T(0)   # placeholder; actual reversal done by index
  # Use a reversed index seq uploaded to the backend
  var tmp = newSeq[T](buf.totalSamples)
  let cpu = buf.data.toSeq()   # one CPU readback to build the reversed seq
  for f in 0..<frames:
    for c in 0..<chans:
      tmp[f * chans + c] = cpu[(frames - 1 - f) * chans + c]
  CSampledBuf[B, T](
    data:       tmp.toGPU(),
    nframes:    buf.nframes,
    nchannels:  buf.nchannels,
    sampleRate: buf.sampleRate
  )

proc reverseInto*[B, T](buf: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write reversed frames into `dst`.
  dst = buf.reverse()

proc reverseIP*[B, T](buf: var CSampledBuf[B, T]) =
  ## In-place reverse.
  buf = buf.reverse()

##########################################################################################################################################################
## PAN — constant-power stereo
##########################################################################################################################################################
##
## `position` ∈ [-1.0, 1.0]:  -1 = hard left,  0 = centre,  +1 = hard right.
## Buffer must be stereo (nchannels == 2), samples interleaved [L, R, L, R, ...].

proc pan*[B, T](buf: CSampledBuf[B, T], position: T): CSampledBuf[B, T] =
  ## Return a new stereo buffer panned to `position` using the constant-power law.
  assert buf.nchannels == 2, "pan: buffer must be stereo"
  let angle = (position + T(1.0)) * T(math.PI / 4.0)
  let gl    = T(cos(float(angle)))
  let gr    = T(sin(float(angle)))
  let frames = buf.nframes.int
  # Build per-sample gain seq: [gl, gr, gl, gr, ...]
  var gains = newSeq[T](buf.totalSamples)
  for f in 0..<frames:
    gains[f * 2]     = gl
    gains[f * 2 + 1] = gr
  CSampledBuf[B, T](
    data:       buf.data * gains.toGPU(),
    nframes:    buf.nframes,
    nchannels:  2,
    sampleRate: buf.sampleRate
  )

proc panInto*[B, T](buf: CSampledBuf[B, T], position: T,
                                dst: var CSampledBuf[B, T]) =
  ## Write panned samples into `dst`.
  dst = buf.pan(position)

proc panIP*[B, T](buf: var CSampledBuf[B, T], position: T) =
  ## In-place pan.
  buf = buf.pan(position)

##########################################################################################################################################################
## CHANNEL CONVERSION
##########################################################################################################################################################

proc toMono*[B, T](buf: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a mono buffer by averaging all channels for each frame.
  let frames = buf.nframes.int
  let chans  = buf.nchannels.int
  let cpu    = buf.data.toSeq()
  var mono   = newSeq[T](frames)
  for f in 0..<frames:
    var sum = T(0)
    for c in 0..<chans:
      sum += cpu[f * chans + c]
    mono[f] = sum / T(chans)
  CSampledBuf[B, T](
    data:       mono.toGPU(),
    nframes:    buf.nframes,
    nchannels:  1,
    sampleRate: buf.sampleRate
  )

proc toMonoInto*[B, T](buf: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write mono-downmix into `dst`.
  dst = buf.toMono()

proc toStereo*[B, T](buf: CSampledBuf[B, T]): CSampledBuf[B, T] =
  ## Return a stereo buffer by duplicating a mono source to both channels.
  ## Returns `buf` unchanged if already stereo.
  if buf.nchannels == 2: return buf
  assert buf.nchannels == 1, "toStereo: only mono → stereo conversion is supported"
  let frames = buf.nframes.int
  let cpu    = buf.data.toSeq()
  var stereo = newSeq[T](frames * 2)
  for f in 0..<frames:
    stereo[f * 2]     = cpu[f]
    stereo[f * 2 + 1] = cpu[f]
  CSampledBuf[B, T](
    data:       stereo.toGPU(),
    nframes:    buf.nframes,
    nchannels:  2,
    sampleRate: buf.sampleRate
  )

proc toStereoInto*[B, T](buf: CSampledBuf[B, T], dst: var CSampledBuf[B, T]) =
  ## Write mono → stereo result into `dst`.
  dst = buf.toStereo()

##########################################################################################################################################################
## MIX DOWN — N channels → M channels
##########################################################################################################################################################

proc mixDown*[B, T](buf: CSampledBuf[B, T],
                                targetChannels: uint16): CSampledBuf[B, T] =
  ## Return a new buffer with `targetChannels` channels by averaging groups
  ## of source channels.  `buf.nchannels` must be divisible by `targetChannels`.
  assert buf.nchannels mod targetChannels == 0,
    "mixDown: nchannels must be divisible by targetChannels"
  let frames  = buf.nframes.int
  let srcCh   = buf.nchannels.int
  let dstCh   = targetChannels.int
  let ratio   = srcCh div dstCh
  let cpu     = buf.data.toSeq()
  var result  = newSeq[T](frames * dstCh)
  for f in 0..<frames:
    for d in 0..<dstCh:
      var sum = T(0)
      for r in 0..<ratio:
        sum += cpu[f * srcCh + d * ratio + r]
      result[f * dstCh + d] = sum / T(ratio)
  CSampledBuf[B, T](
    data:       result.toGPU(),
    nframes:    buf.nframes,
    nchannels:  targetChannels,
    sampleRate: buf.sampleRate
  )

proc mixDownInto*[B, T](buf: CSampledBuf[B, T], targetChannels: uint16,
                                    dst: var CSampledBuf[B, T]) =
  ## Write channel-downmix result into `dst`.
  dst = buf.mixDown(targetChannels)