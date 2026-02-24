#############################################################################################################################
################################################## LINEAR ALGEBRA ###########################################################
#############################################################################################################################

import math

include "vectors.nim"
include "matrix.nim"
include "quaternions.nim"
include "ray.nim"
include "random_distributions.nim"

type MyVec3 = object
  x*, y*, z*: float32
let a = MyVec3(x:1, y:2, z:3)
let b = MyVec3(x:4, y:5, z:6)
echo dot(a, b)        # 32.0
echo cross(a, b)      # MyVec3(x:-3, y:6, z:-3)
echo normalize(a)     # MyVec3 with unit length
