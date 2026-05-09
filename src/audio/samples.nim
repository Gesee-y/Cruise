##########################################################################################################################################################
################################################################## AUDIO SAMPLES #########################################################################
##########################################################################################################################################################
##
## Core buffer type for multichannel sampled audio data.
##
## `CSampledBuf[B, T]` is the central type of the audio pipeline.  `B` is the
## backing store type (e.g. `CLSeq[T]` for GPU, `CPUSeq[T]` for CPU) and `T`
## is the sample element type (typically `float32`).
##
## Backends provide their own `newCSampledBuf` and `toCSampledBuf` constructors
## by specialising on their concrete `B` type.  Everything else — DSP, mixing,
## transfer — is generic and works on any `B` that satisfies the backend contract.
##
## Convenience aliases:
##   CSampledBufCL[T]  — GPU-backed buffer  (requires OpenCL backend)
##   CSampledBufCPU[T] — CPU-backed buffer  (always available)
##
## Layout:
##   Samples are stored interleaved: [L0, R0, L1, R1, ...] for stereo,
##   or [C0, C1, ..., CN, C0, C1, ..., CN, ...] for N channels.
##   Total element count = nframes * nchannels.

type
  CSampledBuf*[B, T] = object
    ## Multichannel audio buffer backed by storage type `B`.
    ##
    ## `B` is either a `CLSeq[T]` (GPU) or a `CPUSeq[T]` (CPU).
    ## `T` is the sample type, typically `float32`.
    ##
    ## All fields are public so backends can construct values directly,
    ## but prefer the constructor procs for normal use.
    data*:       B       ## Backing storage — lives on GPU or CPU depending on backend
    nchannels*:  uint16  ## Number of interleaved audio channels (1 = mono, 2 = stereo…)
    nframes*:    uint32  ## Number of audio frames (samples per channel)
    sampleRate*: uint32  ## Sample rate in Hz (e.g. 44100, 48000)

##########################################################################################################################################################
## ACCESSORS
##########################################################################################################################################################

template getSampleRate*[B, T](s: CSampledBuf[B, T]): uint32 =
  ## Return the sample rate of `s` in Hz.
  s.sampleRate

template getNChannels*[B, T](s: CSampledBuf[B, T]): uint16 =
  ## Return the number of interleaved channels in `s`.
  s.nchannels

template getNFrames*[B, T](s: CSampledBuf[B, T]): uint32 =
  ## Return the number of audio frames in `s`.
  s.nframes

template totalSamples*[B, T](s: CSampledBuf[B, T]): int =
  ## Return the total number of samples in `s` (nframes * nchannels).
  s.nframes.int * s.nchannels.int

##########################################################################################################################################################
## COMMON OPERATIONS — backend-agnostic
##########################################################################################################################################################

proc toCPUSeq*[B, T](buf: CSampledBuf[B, T]): seq[T] =
  ## Transfer the buffer contents to a CPU `seq[T]`.
  ##
  ## For GPU-backed buffers this triggers a blocking GPU → CPU transfer.
  ## For CPU-backed buffers this is a simple copy of the underlying seq.
  ##
  ## Call `clWaitForCPU()` before this if you want explicit control over
  ## the GPU synchronisation point (though `toSeq` is already blocking).
  buf.data.toSeq()

proc slice*[B, T](buf: CSampledBuf[B, T], startFrame, endFrame: uint32): CSampledBuf[B, T] =
  ## Return a logical view into `buf` covering frames [startFrame, endFrame).
  ##
  ## No data is copied — the result shares the same backing memory as `buf`.
  ## For GPU buffers this is a zero-copy `toOpenArray` on the underlying CLSeq.
  let startSample = startFrame.int * buf.nchannels.int
  let endSample   = endFrame.int   * buf.nchannels.int
  CSampledBuf[B, T](
    data:       buf.data.toOpenArray(startSample, endSample),
    nframes:    endFrame - startFrame,
    nchannels:  buf.nchannels,
    sampleRate: buf.sampleRate
  )