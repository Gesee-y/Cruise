##########################################################################################################################################################
################################################################## AUDIO HOST ABSTRACTION ################################################################
##########################################################################################################################################################

type
  CHost[H, D, S] = object
    data: H

proc isAvailable*[H, D, S](host: CHost[H, D, S]): bool {.error: "Backend must implement isAvailable".}
proc devices*[H, D, S](host: CHost[H, D, S]): seq[CDevice[D]] {.error: "Backend must implement devices".}
proc defaultInputDevice*[H, D, S](host: CHost[H, D, S]): CDevice[D] {.error: "Backend must implement defaultInputDevice".}
proc defaultOutputDevice*[H, D, S](host: CHost[H, D, S]): CDevice[D] {.error: "Backend must implement defaultOutputDevice".}
proc createStream*[H, D, S](host: CHost[H, D, S], device: CDevice[D], config: CStreamConfig): CStream[S] {.error: "Backend must implement createStream".}

