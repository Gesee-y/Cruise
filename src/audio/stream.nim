##########################################################################################################################################################
################################################################# AUDIO STREAM ABSTRACTION ###############################################################
##########################################################################################################################################################

type
  CStreamError = enum
    cseNone
    cseUnderflow
    cseOverflow
    cseDeviceLost
    cseUnknown

  CSampleFormat = enum
    csfInt16, csfInt32, csfFloat32, csfFloat64

  CStreamConfig = object
    sampleRate: uint32
    channels: uint16
    format: CSampleFormat
    bufferSize: uint32

  CStreamConfigRange = object
    minSampleRate: uint32
    maxSampleRate: uint32
    minChannels: uint16
    maxChannels: uint16
    formats: set[CSampleFormat]  # formats supportés par cette plage

  CStreamState = enum
    cssIdle, cssPlaying, cssPaused, cssError

  CStream[S] = object
    data: S
    configRange: CStreamConfigRange
    config: CStreamConfig
    state: CStreamState

proc defaultStreamConfig(): CStreamConfig =
  result.sampleRate = 44100
  result.channels = 2
  result.format = csfFloat32
  result.bufferSize = 4096
proc contains*(range: CStreamConfigRange, config: CStreamConfig): bool =
  config.sampleRate >= range.minSampleRate and
  config.sampleRate <= range.maxSampleRate and
  config.channels >= range.minChannels and
  config.channels <= range.maxChannels and
  config.format in range.formats
proc play*[S](data: CStream[S]) {.error: "Backends must implement this function for their streams".}
proc pause*[S](data: CStream[S]) {.error: "Backends must implement this function for their streams".}
proc now*[S](data: CStream[S]) {.error: "Backends must implement this function for their streams".}
proc writeSamples*[S](stream: CStream[S], buffer: openArray[float32]): CStreamError {.error: "Backend must implement writeSamples".}
proc readSamples*[S](stream: CStream[S], buffer: var openArray[float32]): CStreamError {.error: "Backend must implement readSamples".}
template sampleRate*[S](s: CStream[S]): uint32 = s.config.sampleRate
template bufferSize*[S](s: CStream[S]): uint32 = s.config.bufferSize


