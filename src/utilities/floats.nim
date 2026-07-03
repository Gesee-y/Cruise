# ############################################################################################################################ #
# ################################################# Float 16 implementation ################################################## #
# ############################################################################################################################ #

# A float16 is of the form
# sign - exponent - mantissa
#  1   -    5     -    10

type
  float16 {.importc: "float16_t", header: "<stdfloat.h>".} = object

template sign_mask(_: typedesc[float16]): untyped =        0x8000
template exponent_mask(_: typedesc[float16]): untyped =    0x7c00
template exponent_one(_: typedesc[float16]): untyped =     0x3c00
template exponent_half(_: typedesc[float16]): untyped =    0x3800
template significand_mask(_: typedesc[float16]): untyped = 0x03ff
template exponent_max(t: typedesc[float16]): untyped =
  let em = exponent_mask(t)
  let sb = getTrailingZerosCount(significand_mask(t))
  let eb = exponent_one(t) shl sb
  (em shl sb) - eb - 1
