#############################################################################################################################
#################################################### MATRIX #################################################################
#############################################################################################################################
##
## Mat2, Mat3, Mat4 — column-major storage (OpenGL/Vulkan convention).
##
## Storage layout (column-major, matching GPU memory):
##   Mat4.m: array[16, MFloat]
##   Column c, row r  →  index = c * N + r
##
##   Mat4 columns:
##     col 0 : m[0..3]
##     col 1 : m[4..7]
##     col 2 : m[8..11]
##     col 3 : m[12..15]
##
## All matrix × vector multiplies accept ANY type satisfying Vec2/Vec3/Vec4 —
## the result is returned as the same concrete type T.
##

# This file is meant to be imported alongside LA.nim which defines
# MFloat, Vec2, Vec3, Vec4 and all vector generics.

import math

#############################################################################################################################
################################################## TYPES ####################################################################
#############################################################################################################################

type
  Mat2* = object
    ## 2×2 column-major matrix.  m[col*2 + row]
    m*: array[4, MFloat]

  Mat3* = object
    ## 3×3 column-major matrix.  m[col*3 + row]
    m*: array[9, MFloat]

  Mat4* = object
    ## 4×4 column-major matrix.  m[col*4 + row]
    ## Laid out identically to OpenGL / Vulkan / GLSL mat4.
    m*: array[16, MFloat]


#############################################################################################################################
################################################## INDEX HELPERS ############################################################
#############################################################################################################################
# Inline index helpers keep the formula in one place and let every
# access be a simple constant-foldable array subscript.

func idx2(col, row: int): int {.inline.} = col * 2 + row
func idx3(col, row: int): int {.inline.} = col * 3 + row
func idx4(col, row: int): int {.inline.} = col * 4 + row

func `[]`*(mat: Mat2, col, row: int): MFloat {.inline.} =
  ## Read element at (col, row).
  mat.m[idx2(col, row)]

func `[]=`*(mat: var Mat2, col, row: int, v: MFloat) {.inline.} =
  ## Write element at (col, row).
  mat.m[idx2(col, row)] = v

func `[]`*(mat: Mat3, col, row: int): MFloat {.inline.} =
  mat.m[idx3(col, row)]

func `[]=`*(mat: var Mat3, col, row: int, v: MFloat) {.inline.} =
  mat.m[idx3(col, row)] = v

func `[]`*(mat: Mat4, col, row: int): MFloat {.inline.} =
  mat.m[idx4(col, row)]

func `[]=`*(mat: var Mat4, col, row: int, v: MFloat) {.inline.} =
  mat.m[idx4(col, row)] = v


#############################################################################################################################
################################################## IDENTITY / ZERO ##########################################################
#############################################################################################################################

func mat2Identity*(): Mat2 {.inline.} =
  ## Return the 2×2 identity matrix.
  Mat2(m: [1f,0f,
           0f,1f])

func mat3Identity*(): Mat3 {.inline.} =
  ## Return the 3×3 identity matrix.
  Mat3(m: [1f,0f,0f,
           0f,1f,0f,
           0f,0f,1f])

func mat4Identity*(): Mat4 {.inline.} =
  ## Return the 4×4 identity matrix.
  Mat4(m: [1f,0f,0f,0f,
           0f,1f,0f,0f,
           0f,0f,1f,0f,
           0f,0f,0f,1f])

func mat2Zero*(): Mat2 {.inline.} =
  ## All-zero 2×2 matrix (additive identity).
  Mat2(m: [0f,0f,0f,0f])

func mat3Zero*(): Mat3 {.inline.} =
  Mat3(m: [0f,0f,0f,0f,0f,0f,0f,0f,0f])

func mat4Zero*(): Mat4 {.inline.} =
  Mat4(m: [0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f,0f])


#############################################################################################################################
################################################## CONSTRUCTION FROM COLUMNS ################################################
#############################################################################################################################

func mat2*(c0x,c0y, c1x,c1y: MFloat): Mat2 {.inline.} =
  ## Build Mat2 from 4 scalars (column-major order).
  Mat2(m: [c0x,c0y, c1x,c1y])

func mat2*[V: Vec2](col0, col1: V): Mat2 {.inline.} =
  ## Build Mat2 from two Vec2 columns. Accepts any Vec2-compatible type.
  Mat2(m: [col0.x, col0.y,
           col1.x, col1.y])

func mat3*(c0x,c0y,c0z, c1x,c1y,c1z, c2x,c2y,c2z: MFloat): Mat3 {.inline.} =
  ## Build Mat3 from 9 scalars (column-major order).
  Mat3(m: [c0x,c0y,c0z, c1x,c1y,c1z, c2x,c2y,c2z])

func mat3*[V: Vec3](col0, col1, col2: V): Mat3 {.inline.} =
  ## Build Mat3 from three Vec3 columns. Accepts any Vec3-compatible type.
  Mat3(m: [col0.x, col0.y, col0.z,
           col1.x, col1.y, col1.z,
           col2.x, col2.y, col2.z])

func mat4*(c0x,c0y,c0z,c0w,
           c1x,c1y,c1z,c1w,
           c2x,c2y,c2z,c2w,
           c3x,c3y,c3z,c3w: MFloat): Mat4 {.inline.} =
  ## Build Mat4 from 16 scalars (column-major order).
  Mat4(m: [c0x,c0y,c0z,c0w,
           c1x,c1y,c1z,c1w,
           c2x,c2y,c2z,c2w,
           c3x,c3y,c3z,c3w])

func mat4*[V: Vec4](col0, col1, col2, col3: V): Mat4 {.inline.} =
  ## Build Mat4 from four Vec4 columns. Accepts any Vec4-compatible type.
  Mat4(m: [col0.x, col0.y, col0.z, col0.w,
           col1.x, col1.y, col1.z, col1.w,
           col2.x, col2.y, col2.z, col2.w,
           col3.x, col3.y, col3.z, col3.w])

func mat4*(upper: Mat3): Mat4 {.inline.} =
  ## Embed a Mat3 into the upper-left corner of a Mat4 (identity padding).
  ## Useful for converting a rotation/scale matrix to homogeneous form.
  result = mat4Identity()
  result[0,0] = upper[0,0]
  result[0,1] = upper[0,1]
  result[0,2] = upper[0,2]
  result[1,0] = upper[1,0]
  result[1,1] = upper[1,1]
  result[1,2] = upper[1,2]
  result[2,0] = upper[2,0]
  result[2,1] = upper[2,1]
  result[2,2] = upper[2,2]


#############################################################################################################################
################################################## COLUMN / ROW ACCESS ######################################################
#############################################################################################################################

func col0*(m: Mat2): (MFloat,MFloat) {.inline.} = (m.m[0], m.m[1])
func col1*(m: Mat2): (MFloat,MFloat) {.inline.} = (m.m[2], m.m[3])

func col*[V: Vec3](mat: Mat3, c: int, outType: typedesc[V]): V {.inline.} =
  ## Extract column c as any Vec3-compatible type.
  let base = c * 3
  V(x: mat.m[base], y: mat.m[base+1], z: mat.m[base+2])

func col*[V: Vec4](mat: Mat4, c: int, outType: typedesc[V]): V {.inline.} =
  ## Extract column c as any Vec4-compatible type.
  let base = c * 4
  V(x: mat.m[base], y: mat.m[base+1], z: mat.m[base+2], w: mat.m[base+3])

func row*[V: Vec3](mat: Mat3, r: int, outType: typedesc[V]): V {.inline.} =
  ## Extract row r as any Vec3-compatible type.
  V(x: mat.m[r], y: mat.m[3+r], z: mat.m[6+r])

func row*[V: Vec4](mat: Mat4, r: int, outType: typedesc[V]): V {.inline.} =
  ## Extract row r as any Vec4-compatible type.
  V(x: mat.m[r], y: mat.m[4+r], z: mat.m[8+r], w: mat.m[12+r])

func setCol*[V: Vec3](mat: var Mat3, c: int, v: V) {.inline.} =
  ## Set column c from any Vec3-compatible value.
  let base = c * 3
  mat.m[base] = v.x; mat.m[base+1] = v.y; mat.m[base+2] = v.z

func setCol*[V: Vec4](mat: var Mat4, c: int, v: V) {.inline.} =
  ## Set column c from any Vec4-compatible value.
  let base = c * 4
  mat.m[base] = v.x; mat.m[base+1] = v.y; mat.m[base+2] = v.z; mat.m[base+3] = v.w


#############################################################################################################################
################################################## EQUALITY #################################################################
#############################################################################################################################

func `==`*(a, b: Mat2): bool {.inline.} = a.m == b.m
func `==`*(a, b: Mat3): bool {.inline.} = a.m == b.m
func `==`*(a, b: Mat4): bool {.inline.} = a.m == b.m

func approxEq*(a, b: Mat2, eps: MFloat = 1e-6f): bool {.inline.} =
  ## Component-wise approximate equality.
  for i in 0..3:
    if abs(a.m[i] - b.m[i]) > eps: return false
  true

func approxEq*(a, b: Mat3, eps: MFloat = 1e-6f): bool {.inline.} =
  for i in 0..8:
    if abs(a.m[i] - b.m[i]) > eps: return false
  true

func approxEq*(a, b: Mat4, eps: MFloat = 1e-6f): bool {.inline.} =
  for i in 0..15:
    if abs(a.m[i] - b.m[i]) > eps: return false
  true


#############################################################################################################################
################################################## SCALAR ARITHMETIC ########################################################
#############################################################################################################################

func `+`*(a, b: Mat4): Mat4 {.inline.} =
  ## Component-wise addition.
  result.m[0]  = a.m[0]  + b.m[0];  result.m[1]  = a.m[1]  + b.m[1]
  result.m[2]  = a.m[2]  + b.m[2];  result.m[3]  = a.m[3]  + b.m[3]
  result.m[4]  = a.m[4]  + b.m[4];  result.m[5]  = a.m[5]  + b.m[5]
  result.m[6]  = a.m[6]  + b.m[6];  result.m[7]  = a.m[7]  + b.m[7]
  result.m[8]  = a.m[8]  + b.m[8];  result.m[9]  = a.m[9]  + b.m[9]
  result.m[10] = a.m[10] + b.m[10]; result.m[11] = a.m[11] + b.m[11]
  result.m[12] = a.m[12] + b.m[12]; result.m[13] = a.m[13] + b.m[13]
  result.m[14] = a.m[14] + b.m[14]; result.m[15] = a.m[15] + b.m[15]

func `-`*(a, b: Mat4): Mat4 {.inline.} =
  result.m[0]  = a.m[0]  - b.m[0];  result.m[1]  = a.m[1]  - b.m[1]
  result.m[2]  = a.m[2]  - b.m[2];  result.m[3]  = a.m[3]  - b.m[3]
  result.m[4]  = a.m[4]  - b.m[4];  result.m[5]  = a.m[5]  - b.m[5]
  result.m[6]  = a.m[6]  - b.m[6];  result.m[7]  = a.m[7]  - b.m[7]
  result.m[8]  = a.m[8]  - b.m[8];  result.m[9]  = a.m[9]  - b.m[9]
  result.m[10] = a.m[10] - b.m[10]; result.m[11] = a.m[11] - b.m[11]
  result.m[12] = a.m[12] - b.m[12]; result.m[13] = a.m[13] - b.m[13]
  result.m[14] = a.m[14] - b.m[14]; result.m[15] = a.m[15] - b.m[15]

func `*`*(mat: Mat4, s: MFloat): Mat4 {.inline.} =
  ## Scale all elements by scalar s.
  for i in 0..15: result.m[i] = mat.m[i] * s

func `*`*(s: MFloat, mat: Mat4): Mat4 {.inline.} = mat * s

func `+=`*(a: var Mat4, b: Mat4) {.inline.} =
  for i in 0..15: a.m[i] += b.m[i]

func `-=`*(a: var Mat4, b: Mat4) {.inline.} =
  for i in 0..15: a.m[i] -= b.m[i]

# Mat3 scalar ops
func `*`*(mat: Mat3, s: MFloat): Mat3 {.inline.} =
  for i in 0..8: result.m[i] = mat.m[i] * s

func `*`*(s: MFloat, mat: Mat3): Mat3 {.inline.} = mat * s

func `+`*(a, b: Mat3): Mat3 {.inline.} =
  for i in 0..8: result.m[i] = a.m[i] + b.m[i]

func `-`*(a, b: Mat3): Mat3 {.inline.} =
  for i in 0..8: result.m[i] = a.m[i] - b.m[i]


#############################################################################################################################
################################################## MATRIX × MATRIX ##########################################################
#############################################################################################################################
# Fully unrolled — no loop overhead, compiler can schedule / vectorise freely.

func `*`*(a, b: Mat2): Mat2 {.inline.} =
  ## Mat2 × Mat2 — 8 multiplies, 4 adds.
  let
    a00 = a.m[0]
    a10 = a.m[1]
    a01 = a.m[2]
    a11 = a.m[3]
    b00 = b.m[0]
    b10 = b.m[1]
    b01 = b.m[2]
    b11 = b.m[3]
  Mat2(m:[
    a00*b00 + a01*b10,
    a10*b00 + a11*b10,
    a00*b01 + a01*b11,
    a10*b01 + a11*b11
  ])

func `*`*(a, b: Mat3): Mat3 {.inline.} =
  ## Mat3 × Mat3 — 27 multiplies, 18 adds, fully unrolled.
  let
    # column 0 of a
    a00=a.m[0]
    a10=a.m[1]
    a20=a.m[2]
    # column 1 of a
    a01=a.m[3]
    a11=a.m[4]
    a21=a.m[5]
    # column 2 of a
    a02=a.m[6]
    a12=a.m[7]
    a22=a.m[8]
    # columns of b
    b00=b.m[0]
    b10=b.m[1]
    b20=b.m[2]
    b01=b.m[3]
    b11=b.m[4]
    b21=b.m[5]
    b02=b.m[6]
    b12=b.m[7]
    b22=b.m[8]
  Mat3(m:[
    a00*b00 + a01*b10 + a02*b20,  # [0,0]
    a10*b00 + a11*b10 + a12*b20,  # [1,0]
    a20*b00 + a21*b10 + a22*b20,  # [2,0]
    a00*b01 + a01*b11 + a02*b21,  # [0,1]
    a10*b01 + a11*b11 + a12*b21,  # [1,1]
    a20*b01 + a21*b11 + a22*b21,  # [2,1]
    a00*b02 + a01*b12 + a02*b22,  # [0,2]
    a10*b02 + a11*b12 + a12*b22,  # [1,2]
    a20*b02 + a21*b12 + a22*b22   # [2,2]
  ])

func `*`*(a, b: Mat4): Mat4 {.inline.} =
  ## Mat4 × Mat4 — 64 multiplies, 48 adds, fully unrolled.
  ## Column-major traversal gives optimal cache access on the left operand.
  let
    # columns of a
    a00=a.m[0]
    a10=a.m[1]
    a20=a.m[2]
    a30=a.m[3]
    a01=a.m[4]
    a11=a.m[5]
    a21=a.m[6]
    a31=a.m[7]
    a02=a.m[8]
    a12=a.m[9]
    a22=a.m[10]
    a32=a.m[11]
    a03=a.m[12]
    a13=a.m[13]
    a23=a.m[14]
    a33=a.m[15]
    # columns of b
    b00=b.m[0]
    b10=b.m[1]
    b20=b.m[2]
    b30=b.m[3]
    b01=b.m[4]
    b11=b.m[5]
    b21=b.m[6]
    b31=b.m[7]
    b02=b.m[8]
    b12=b.m[9]
    b22=b.m[10]
    b32=b.m[11]
    b03=b.m[12]
    b13=b.m[13]
    b23=b.m[14]
    b33=b.m[15]
  Mat4(m:[
    # result column 0
    a00*b00 + a01*b10 + a02*b20 + a03*b30,
    a10*b00 + a11*b10 + a12*b20 + a13*b30,
    a20*b00 + a21*b10 + a22*b20 + a23*b30,
    a30*b00 + a31*b10 + a32*b20 + a33*b30,
    # result column 1
    a00*b01 + a01*b11 + a02*b21 + a03*b31,
    a10*b01 + a11*b11 + a12*b21 + a13*b31,
    a20*b01 + a21*b11 + a22*b21 + a23*b31,
    a30*b01 + a31*b11 + a32*b21 + a33*b31,
    # result column 2
    a00*b02 + a01*b12 + a02*b22 + a03*b32,
    a10*b02 + a11*b12 + a12*b22 + a13*b32,
    a20*b02 + a21*b12 + a22*b22 + a23*b32,
    a30*b02 + a31*b12 + a32*b22 + a33*b32,
    # result column 3
    a00*b03 + a01*b13 + a02*b23 + a03*b33,
    a10*b03 + a11*b13 + a12*b23 + a13*b33,
    a20*b03 + a21*b13 + a22*b23 + a23*b33,
    a30*b03 + a31*b13 + a32*b23 + a33*b33
  ])

func `*=`*(a: var Mat4, b: Mat4) {.inline.} = a = a * b
func `*=`*(a: var Mat3, b: Mat3) {.inline.} = a = a * b


#############################################################################################################################
################################################## MATRIX × VECTOR ##########################################################
#############################################################################################################################
# Generic: works with ANY type satisfying Vec2/Vec3/Vec4.
# Returns the same concrete type V so no casting is needed by the caller.

func `*`*[V: Vec2](mat: Mat2, v: V): V {.inline.} =
  ## Mat2 × Vec2 — transform a 2D vector.
  ## Works with any type satisfying the Vec2 concept.
  V(x: mat.m[0]*v.x + mat.m[2]*v.y,
    y: mat.m[1]*v.x + mat.m[3]*v.y)

func `*`*[V: Vec3](mat: Mat3, v: V): V {.inline.} =
  ## Mat3 × Vec3 — transform a 3D vector (no translation).
  ## Works with any type satisfying the Vec3 concept.
  V(x: mat.m[0]*v.x + mat.m[3]*v.y + mat.m[6]*v.z,
    y: mat.m[1]*v.x + mat.m[4]*v.y + mat.m[7]*v.z,
    z: mat.m[2]*v.x + mat.m[5]*v.y + mat.m[8]*v.z)

func `*`*[V: Vec4](mat: Mat4, v: V): V {.inline.} =
  ## Mat4 × Vec4 — full homogeneous transform.
  ## Works with any type satisfying the Vec4 concept.
  V(x: mat.m[0]*v.x + mat.m[4]*v.y + mat.m[8]*v.z  + mat.m[12]*v.w,
    y: mat.m[1]*v.x + mat.m[5]*v.y + mat.m[9]*v.z  + mat.m[13]*v.w,
    z: mat.m[2]*v.x + mat.m[6]*v.y + mat.m[10]*v.z + mat.m[14]*v.w,
    w: mat.m[3]*v.x + mat.m[7]*v.y + mat.m[11]*v.z + mat.m[15]*v.w)

func transformPoint*[V: Vec3](mat: Mat4, v: V): V {.inline.} =
  ## Transform a 3D POINT by a Mat4 (w=1 implied — includes translation).
  ## Equivalent to mat * vec4(v, 1.0) then dropping w.
  ## Works with any Vec3-compatible type.
  V(x: mat.m[0]*v.x + mat.m[4]*v.y + mat.m[8]*v.z  + mat.m[12],
    y: mat.m[1]*v.x + mat.m[5]*v.y + mat.m[9]*v.z  + mat.m[13],
    z: mat.m[2]*v.x + mat.m[6]*v.y + mat.m[10]*v.z + mat.m[14])

func transformDir*[V: Vec3](mat: Mat4, v: V): V {.inline.} =
  ## Transform a 3D DIRECTION by a Mat4 (w=0 implied — no translation).
  ## Use for normals, velocities, axes — anything that must not shift.
  ## Works with any Vec3-compatible type.
  V(x: mat.m[0]*v.x + mat.m[4]*v.y + mat.m[8]*v.z,
    y: mat.m[1]*v.x + mat.m[5]*v.y + mat.m[9]*v.z,
    z: mat.m[2]*v.x + mat.m[6]*v.y + mat.m[10]*v.z)

func transformNormal*[V: Vec3](invTransposeMat: Mat4, n: V): V {.inline.} =
  ## Transform a surface normal correctly using the inverse-transpose matrix.
  ## Pass mat.inverseTranspose() as invTransposeMat.
  ## Works with any Vec3-compatible type.
  V(x: invTransposeMat.m[0]*n.x + invTransposeMat.m[4]*n.y + invTransposeMat.m[8]*n.z,
    y: invTransposeMat.m[1]*n.x + invTransposeMat.m[5]*n.y + invTransposeMat.m[9]*n.z,
    z: invTransposeMat.m[2]*n.x + invTransposeMat.m[6]*n.y + invTransposeMat.m[10]*n.z)


#############################################################################################################################
################################################## TRANSPOSE ################################################################
#############################################################################################################################

func transpose*(mat: Mat2): Mat2 {.inline.} =
  ## Transpose (flip rows and columns).
  Mat2(m:[mat.m[0], mat.m[2],
          mat.m[1], mat.m[3]])

func transpose*(mat: Mat3): Mat3 {.inline.} =
  Mat3(m:[mat.m[0], mat.m[3], mat.m[6],
          mat.m[1], mat.m[4], mat.m[7],
          mat.m[2], mat.m[5], mat.m[8]])

func transpose*(mat: Mat4): Mat4 {.inline.} =
  Mat4(m:[mat.m[0],  mat.m[4],  mat.m[8],  mat.m[12],
          mat.m[1],  mat.m[5],  mat.m[9],  mat.m[13],
          mat.m[2],  mat.m[6],  mat.m[10], mat.m[14],
          mat.m[3],  mat.m[7],  mat.m[11], mat.m[15]])


#############################################################################################################################
################################################## DETERMINANT ##############################################################
#############################################################################################################################

func determinant*(mat: Mat2): MFloat {.inline.} =
  ## Determinant of a 2×2 matrix.
  mat.m[0]*mat.m[3] - mat.m[2]*mat.m[1]

func determinant*(mat: Mat3): MFloat {.inline.} =
  ## Determinant of a 3×3 matrix via cofactor expansion along column 0.
  let
    a=mat.m[0]
    b=mat.m[1]
    c=mat.m[2]
    d=mat.m[3]
    e=mat.m[4]
    f=mat.m[5]
    g=mat.m[6]
    h=mat.m[7]
    i=mat.m[8]
  a*(e*i - f*h) - d*(b*i - c*h) + g*(b*f - c*e)

func determinant*(mat: Mat4): MFloat =
  ## Determinant of a 4×4 matrix.
  ## Uses cofactor expansion with sub-determinants cached to minimise work.
  let m = mat.m
  # 2×2 sub-determinants of the bottom-right 3×3 block (cofactors)
  let
    s0 = m[0]*m[5]   - m[4]*m[1]
    s1 = m[0]*m[9]   - m[8]*m[1]
    s2 = m[0]*m[13]  - m[12]*m[1]
    s3 = m[4]*m[9]   - m[8]*m[5]
    s4 = m[4]*m[13]  - m[12]*m[5]
    s5 = m[8]*m[13]  - m[12]*m[9]
    c0 = m[2]*m[7]   - m[6]*m[3]
    c1 = m[2]*m[11]  - m[10]*m[3]
    c2 = m[2]*m[15]  - m[14]*m[3]
    c3 = m[6]*m[11]  - m[10]*m[7]
    c4 = m[6]*m[15]  - m[14]*m[7]
    c5 = m[10]*m[15] - m[14]*m[11]
  s0*c5 - s1*c4 + s2*c3 + s3*c2 - s4*c1 + s5*c0


#############################################################################################################################
################################################## INVERSE ##################################################################
#############################################################################################################################

func inverse*(mat: Mat2): Mat2 {.inline.} =
  ## Inverse of a 2×2 matrix. Result is undefined when determinant = 0.
  let invDet = 1f / mat.determinant
  Mat2(m:[ mat.m[3]*invDet, -mat.m[1]*invDet,
          -mat.m[2]*invDet,  mat.m[0]*invDet])

func inverse*(mat: Mat3): Mat3 =
  ## Inverse of a 3×3 matrix via adjugate / determinant.
  let
    a=mat.m[0]
    b=mat.m[1]
    c=mat.m[2]
    d=mat.m[3]
    e=mat.m[4]
    f=mat.m[5]
    g=mat.m[6]
    h=mat.m[7]
    i=mat.m[8]
    # cofactors
    A =  (e*i - f*h)
    B = -(d*i - f*g)
    C =  (d*h - e*g)
    D = -(b*i - c*h)
    E =  (a*i - c*g)
    F = -(a*h - b*g)
    G =  (b*f - c*e)
    H = -(a*f - c*d)
    I =  (a*e - b*d)
    invDet = 1f / (a*A + b*B + c*C)  # det = a·A + b·B + c·C
  # adjugate is transpose of cofactor matrix
  Mat3(m:[ A*invDet, D*invDet, G*invDet,
           B*invDet, E*invDet, H*invDet,
           C*invDet, F*invDet, I*invDet])

func inverse*(mat: Mat4): Mat4 =
  ## Inverse of a 4×4 matrix using the Cramer / cofactor method.
  ## 2×2 sub-determinants are pre-computed and reused — minimises multiplies.
  ## Result is undefined when determinant ≈ 0 (singular matrix).
  let m = mat.m
  let
    s0 = m[0]*m[5]   - m[4]*m[1]
    s1 = m[0]*m[9]   - m[8]*m[1]
    s2 = m[0]*m[13]  - m[12]*m[1]
    s3 = m[4]*m[9]   - m[8]*m[5]
    s4 = m[4]*m[13]  - m[12]*m[5]
    s5 = m[8]*m[13]  - m[12]*m[9]
    c0 = m[2]*m[7]   - m[6]*m[3]
    c1 = m[2]*m[11]  - m[10]*m[3]
    c2 = m[2]*m[15]  - m[14]*m[3]
    c3 = m[6]*m[11]  - m[10]*m[7]
    c4 = m[6]*m[15]  - m[14]*m[7]
    c5 = m[10]*m[15] - m[14]*m[11]
    invDet = 1f / (s0*c5 - s1*c4 + s2*c3 + s3*c2 - s4*c1 + s5*c0)
  Mat4(m:[
    ( m[5]*c5 - m[9]*c4  + m[13]*c3) * invDet,
    (-m[1]*c5 + m[9]*c2  - m[13]*c1) * invDet,
    ( m[1]*c4 - m[5]*c2  + m[13]*c0) * invDet,
    (-m[1]*c3 + m[5]*c1  - m[9]*c0 ) * invDet,
    (-m[4]*c5 + m[8]*c4  - m[12]*c3) * invDet,
    ( m[0]*c5 - m[8]*c2  + m[12]*c1) * invDet,
    (-m[0]*c4 + m[4]*c2  - m[12]*c0) * invDet,
    ( m[0]*c3 - m[4]*c1  + m[8]*c0 ) * invDet,
    ( m[7]*s5 - m[11]*s4 + m[15]*s3) * invDet,
    (-m[3]*s5 + m[11]*s2 - m[15]*s1) * invDet,
    ( m[3]*s4 - m[7]*s2  + m[15]*s0) * invDet,
    (-m[3]*s3 + m[7]*s1  - m[11]*s0) * invDet,
    (-m[6]*s5 + m[10]*s4 - m[14]*s3) * invDet,
    ( m[2]*s5 - m[10]*s2 + m[14]*s1) * invDet,
    (-m[2]*s4 + m[6]*s2  - m[14]*s0) * invDet,
    ( m[2]*s3 - m[6]*s1  + m[10]*s0) * invDet
  ])

func inverseTranspose*(mat: Mat4): Mat4 {.inline.} =
  ## Combined inverse-transpose in one call.
  ## Use to transform surface normals correctly when the matrix has
  ## non-uniform scale or shear.
  mat.inverse.transpose

func inverseOrthogonal*(mat: Mat4): Mat4 {.inline.} =
  ## Fast inverse for ORTHOGONAL matrices (pure rotation / no scale/shear).
  ## The inverse of an orthogonal matrix equals its transpose — O(16) copies.
  ## Verify with mat.determinant ≈ ±1 before using this path.
  mat.transpose

func inverseTRS*(mat: Mat4): Mat4 {.inline.} =
  ## Fast inverse for TRS matrices (Translation × Rotation × uniform Scale).
  ## Extracts scale, inverts rotation via transpose, computes inverse translation.
  ## Much cheaper than the general inverse when you know the matrix is TRS-only.
  ##
  ## Decomposition:
  ##   scale² = |col0|², |col1|², |col2|²
  ##   R_inv  = transpose(R) / scale²
  ##   t_inv  = -R_inv * t
  let
    # squared scale per axis
    sx2 = mat.m[0]*mat.m[0] + mat.m[1]*mat.m[1] + mat.m[2]*mat.m[2]
    sy2 = mat.m[4]*mat.m[4] + mat.m[5]*mat.m[5] + mat.m[6]*mat.m[6]
    sz2 = mat.m[8]*mat.m[8] + mat.m[9]*mat.m[9] + mat.m[10]*mat.m[10]
    isx = 1f / sx2
    isy = 1f / sy2
    isz = 1f / sz2
    # inverse rotation block (transpose / scale²)
    r00 = mat.m[0]*isx
    r10 = mat.m[4]*isx
    r20 = mat.m[8]*isx
    r01 = mat.m[1]*isy
    r11 = mat.m[5]*isy
    r21 = mat.m[9]*isy
    r02 = mat.m[2]*isz
    r12 = mat.m[6]*isz
    r22 = mat.m[10]*isz
    # inverse translation: -R_inv * t
    tx = mat.m[12]
    ty = mat.m[13]
    tz = mat.m[14]
    itx = -(r00*tx + r10*ty + r20*tz)
    ity = -(r01*tx + r11*ty + r21*tz)
    itz = -(r02*tx + r12*ty + r22*tz)
  Mat4(m:[r00, r01, r02, 0f,
          r10, r11, r12, 0f,
          r20, r21, r22, 0f,
          itx, ity, itz, 1f])


#############################################################################################################################
################################################## TRANSFORM CONSTRUCTORS ###################################################
#############################################################################################################################

func mat4Translate*[V: Vec3](t: V): Mat4 {.inline.} =
  ## Translation matrix from any Vec3-compatible type.
  Mat4(m:[1f,  0f,  0f,  0f,
          0f,  1f,  0f,  0f,
          0f,  0f,  1f,  0f,
          t.x, t.y, t.z, 1f])

func mat4Scale*[V: Vec3](s: V): Mat4 {.inline.} =
  ## Non-uniform scale matrix from any Vec3-compatible type.
  Mat4(m:[s.x, 0f,  0f,  0f,
          0f,  s.y, 0f,  0f,
          0f,  0f,  s.z, 0f,
          0f,  0f,  0f,  1f])

func mat4Scale*(s: MFloat): Mat4 {.inline.} =
  ## Uniform scale matrix.
  Mat4(m:[s,  0f, 0f, 0f,
          0f, s,  0f, 0f,
          0f, 0f, s,  0f,
          0f, 0f, 0f, 1f])

func mat4RotateX*(angle: MFloat): Mat4 {.inline.} =
  ## Rotation matrix around the X axis by `angle` radians.
  let c = cos(angle); let s = sin(angle)
  Mat4(m:[1f, 0f, 0f, 0f,
          0f, c,  s,  0f,
          0f, -s, c,  0f,
          0f, 0f, 0f, 1f])

func mat4RotateY*(angle: MFloat): Mat4 {.inline.} =
  ## Rotation matrix around the Y axis by `angle` radians.
  let c = cos(angle); let s = sin(angle)
  Mat4(m:[c,  0f, -s, 0f,
          0f, 1f, 0f, 0f,
          s,  0f, c,  0f,
          0f, 0f, 0f, 1f])

func mat4RotateZ*(angle: MFloat): Mat4 {.inline.} =
  ## Rotation matrix around the Z axis by `angle` radians.
  let c = cos(angle); let s = sin(angle)
  Mat4(m:[c,  s,  0f, 0f,
          -s, c,  0f, 0f,
          0f, 0f, 1f, 0f,
          0f, 0f, 0f, 1f])

func mat4Rotate*[V: Vec3](axis: V, angle: MFloat): Mat4 =
  ## Rotation matrix around an arbitrary unit axis by `angle` radians.
  ## Uses the Rodrigues / angle-axis formula.
  ## `axis` can be any Vec3-compatible type and must be normalized.
  let
    c  = cos(angle)
    s  = sin(angle)
    t  = 1f - c
    x  = axis.x
    y = axis.y
    z = axis.z
    tx = t*x
    ty = t*y
  Mat4(m:[
    tx*x+c,   tx*y+s*z, tx*z-s*y, 0f,
    tx*y-s*z, ty*y+c,   ty*z+s*x, 0f,
    tx*z+s*y, ty*z-s*x, t*z*z+c,  0f,
    0f,       0f,       0f,        1f
  ])

func mat4LookAt*[V: Vec3](eye, center, up: V): Mat4 =
  ## View matrix looking from `eye` towards `center` with `up` defining the
  ## world up direction. All arguments can be any Vec3-compatible type.
  ## Right-handed convention (same as OpenGL gluLookAt).
  let
    # forward = normalize(center - eye)
    fx = center.x - eye.x
    fy = center.y - eye.y
    fz = center.z - eye.z
    flen = 1f / sqrt(fx*fx + fy*fy + fz*fz)
    f0 = fx*flen
    f1 = fy*flen
    f2 = fz*flen
    # right = normalize(forward × up)
    rx = f1*up.z - f2*up.y
    ry = f2*up.x - f0*up.z
    rz = f0*up.y - f1*up.x
    rlen = 1f / sqrt(rx*rx + ry*ry + rz*rz)
    r0 = rx*rlen
    r1 = ry*rlen
    r2 = rz*rlen
    # true up = right × forward
    u0 = r1*f2 - r2*f1
    u1 = r2*f0 - r0*f2
    u2 = r0*f1 - r1*f0
  Mat4(m:[
     r0,              u0,             -f0,             0f,
     r1,              u1,             -f1,             0f,
     r2,              u2,             -f2,             0f,
    -(r0*eye.x + r1*eye.y + r2*eye.z),
    -(u0*eye.x + u1*eye.y + u2*eye.z),
     (f0*eye.x + f1*eye.y + f2*eye.z),
     1f
  ])

func mat4Perspective*(fovY, aspect, zNear, zFar: MFloat): Mat4 {.inline.} =
  ## Perspective projection matrix (right-handed, depth range [-1, 1], OpenGL).
  ## fovY : vertical field-of-view in radians.
  ## aspect: width / height.
  let
    tanHalf = tan(fovY * 0.5f)
    a = 1f / (aspect * tanHalf)
    b = 1f / tanHalf
    c = -(zFar + zNear) / (zFar - zNear)
    d = -(2f * zFar * zNear) / (zFar - zNear)
  Mat4(m:[a,  0f, 0f,  0f,
          0f, b,  0f,  0f,
          0f, 0f, c,  -1f,
          0f, 0f, d,   0f])

func mat4PerspectiveVk*(fovY, aspect, zNear, zFar: MFloat): Mat4 {.inline.} =
  ## Perspective projection for Vulkan (right-handed, depth [0, 1], Y-flipped).
  let
    tanHalf = tan(fovY * 0.5f)
    a = 1f / (aspect * tanHalf)
    b = -(1f / tanHalf)                         # flip Y for Vulkan NDC
    c = zFar / (zNear - zFar)
    d = -(zFar * zNear) / (zFar - zNear)
  Mat4(m:[a,  0f, 0f,  0f,
          0f, b,  0f,  0f,
          0f, 0f, c,  -1f,
          0f, 0f, d,   0f])

func mat4Ortho*(left, right, bottom, top, zNear, zFar: MFloat): Mat4 {.inline.} =
  ## Orthographic projection matrix (right-handed, depth [-1, 1], OpenGL).
  let
    rl = 1f / (right - left)
    tb = 1f / (top - bottom)
    fn = 1f / (zFar - zNear)
  Mat4(m:[
    2f*rl,            0f,               0f,              0f,
    0f,               2f*tb,            0f,              0f,
    0f,               0f,              -2f*fn,           0f,
   -(right+left)*rl, -(top+bottom)*tb, -(zFar+zNear)*fn, 1f
  ])

func mat4TRS*[P, R, S: Vec3](pos: P, euler: R, scale: S): Mat4 {.inline.} =
  ## Compose a TRS matrix from translation, Euler angles (XYZ order), scale.
  ## All three arguments can be any Vec3-compatible type.
  ## Equivalent to mat4Translate(pos) * rotX * rotY * rotZ * mat4Scale(scale).
  mat4Translate(pos) *
  mat4RotateZ(euler.z) *
  mat4RotateY(euler.y) *
  mat4RotateX(euler.x) *
  mat4Scale(scale)


#############################################################################################################################
################################################## STRING REPRESENTATION ####################################################
#############################################################################################################################

func `$`*(mat: Mat2): string =
  ## Pretty-print a Mat2 row by row.
  "[" & $mat.m[0] & ", " & $mat.m[2] & "]\n" &
  "[" & $mat.m[1] & ", " & $mat.m[3] & "]"

func `$`*(mat: Mat3): string =
  ## Pretty-print a Mat3 row by row.
  "[" & $mat.m[0] & ", " & $mat.m[3] & ", " & $mat.m[6] & "]\n" &
  "[" & $mat.m[1] & ", " & $mat.m[4] & ", " & $mat.m[7] & "]\n" &
  "[" & $mat.m[2] & ", " & $mat.m[5] & ", " & $mat.m[8] & "]"

func `$`*(mat: Mat4): string =
  ## Pretty-print a Mat4 row by row.
  "[" & $mat.m[0] & ", " & $mat.m[4] & ", " & $mat.m[8]  & ", " & $mat.m[12] & "]\n" &
  "[" & $mat.m[1] & ", " & $mat.m[5] & ", " & $mat.m[9]  & ", " & $mat.m[13] & "]\n" &
  "[" & $mat.m[2] & ", " & $mat.m[6] & ", " & $mat.m[10] & ", " & $mat.m[14] & "]\n" &
  "[" & $mat.m[3] & ", " & $mat.m[7] & ", " & $mat.m[11] & ", " & $mat.m[15] & "]"