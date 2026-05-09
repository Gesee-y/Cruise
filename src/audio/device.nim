##########################################################################################################################################################
################################################################# AUDIO DEVICE ABSTRACTION ###############################################################
##########################################################################################################################################################

type
  CDeviceDirection = enum
    cddUnknown, cddInput, cddOutput, cddDuplex

  CDeviceId = object
    value: string  # identifiant unique, chaque backend le remplit à sa façon

  CDeviceType = enum
    cdtSpeaker, cdtMicrophone, cdtHeadphones, cdtHeadset, cdtEarpiece, cdtHandset, cdtHearingAid, cdtDock, cdtTuner, cdtVirtual

  CDeviceInterface = enum
    cdiUnknown, cdiBuiltin, cdiBluetooth, cdiUSB, cdiPCI, cdiFirewire, cdiThunderbolt, cdiHDMI, cdiLine, cdiSPDIF, cdiNetwork, cdiVirtual, 
    cdiDisplayPort, cdiAggregate

  CDeviceDescriptor = object
    manufacturer: string
    driver: string
    itype: CDeviceType
    devInterface: CDeviceInterface
    address: string

  CDevice[T] = object
    data: T
    id: CDeviceId
    name: string
    direction: CDeviceDirection
    descriptor: CDeviceDescriptor

template getName(d: CDevice): string = d.name
template getDirection(d: CDevice): CDeviceDirection = d.direction
template getManufacturer(d: CDevice): string = d.descriptor.manufacturer
template getDriver(d: CDevice): string = d.descriptor.driver
template getType(d: CDevice): CDeviceType = d.descriptor.itype
template getInterface(d: CDevice): CDeviceInterface = d.descriptor.devInterface
template getAddress(d: CDevice): string = d.descriptor.address
template getInner(d: CDevice): untyped = d.data
template getStream(d: CDevice) {.error: "Backend must implement this function".}
template supportInput(d: CDevice): bool = d.getDirection in {cddInput, cddDuplex}
template supportOutput(d: CDevice): bool = d.getDirection in {cddOutput, cddDuplex}

proc directionFromCap(hasInput = false, hasOutput = true): CDeviceDirection = ((hasOutput.int shl 1) or hasInput.int).CDeviceDirection

