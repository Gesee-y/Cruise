##########################################################################################################################################################
#################################################################### AUDIO SAMPLES #######################################################################
##########################################################################################################################################################

import ../gpuarray/backend/cl
import options

type
  CSampledBuf*[T] = object
    data*: CLSeq[T]
    nchannels*: uint16
    nframes*: uint32
    sampleRate*: uint32

proc newCSampledBuf*[T](nframes: uint32, nchannels: uint16, sampleRate: uint32 = 44100): CSampledBuf[T] =
  let totalSamples = nframes.int * nchannels.int
  CSampledBuf[T](
    data: newCLSeq[T](totalSamples),
    nframes: nframes,
    nchannels: nchannels,
    sampleRate: sampleRate
  )

proc toCSampledBuf*[T](arr: openArray[T], nchannels: uint16, sampleRate: uint32 = 44100): CSampledBuf[T] =
  let nframes = (arr.len div nchannels.int).uint32
  CSampledBuf[T](
    data: arr.toGPU(),
    nframes: nframes,
    nchannels: nchannels,
    sampleRate: sampleRate
  )

template getSampleRate*[T](s: CSampledBuf[T]): uint32 = s.sampleRate
template getNChannels*[T](s: CSampledBuf[T]): uint16 = s.nchannels
template getNFrames*[T](s: CSampledBuf[T]): uint32 = s.nframes

proc toCPU*[T](buf: CSampledBuf[T]): seq[T] =
  buf.data.toSeq()

proc toOpenArray*[T](buf: CSampledBuf[T], startFrame, endFrame: uint32): CSampledBuf[T] =
  let startSample = startFrame.int * buf.nchannels.int
  let endSample   = endFrame.int   * buf.nchannels.int
  CSampledBuf[T](
    data: buf.data.toOpenArray(startSample, endSample),
    nframes: endFrame - startFrame,
    nchannels: buf.nchannels,
    sampleRate: buf.sampleRate
  )