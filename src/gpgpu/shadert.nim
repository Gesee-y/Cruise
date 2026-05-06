#########################################################################################################################################################
############################################################### NIM SHADER TRANSPILER ###################################################################
#########################################################################################################################################################

import ../../externalLib/shaderc/src/shaderc

type
  ShaderFormat* = enum
    sfGLSL      ## text — glShaderSource
    sfSPIRV     ## binary — glShaderBinary + glSpecializeShader
    sfMSL       ## text — Metal
    sfHLSL      ## text — DirectX
    sfWGSL      ## text — WebGPU

  ShaderResult* = object
    format*:  ShaderFormat
    case isBinary*: bool
    of true:  bytes*:  seq[byte]
    of false: source*: string

  CShaderTarget* = enum
    csVulkan10, csVulkan11, csVulkan12, csVulkan13, csVulkan14,
    csOpenGL, csOpenGLCompat,
    csWebGPU

import transpiler
export transpiler

proc applyTarget*(options: CompileOptionsT; target: CShaderTarget; openglVersion: cint = 430) =
  case target
  of csVulkan10:     setTargetEnv(options, TargetEnv.vulkan,       EnvVersion.vulkan10.ord.cint)
  of csVulkan11:     setTargetEnv(options, TargetEnv.vulkan,       EnvVersion.vulkan11.ord.cint)
  of csVulkan12:     setTargetEnv(options, TargetEnv.vulkan,       EnvVersion.vulkan12.ord.cint)
  of csVulkan13:     setTargetEnv(options, TargetEnv.vulkan,       EnvVersion.vulkan13.ord.cint)
  of csVulkan14:     setTargetEnv(options, TargetEnv.vulkan,       EnvVersion.vulkan14.ord.cint)
  of csOpenGL:       setTargetEnv(options, TargetEnv.opengl,       openglVersion)
  of csOpenGLCompat: setTargetEnv(options, TargetEnv.openglCompat, openglVersion)
  of csWebGPU:       setTargetEnv(options, TargetEnv.webgpu,       EnvVersion.webgpu_enumval.ord.cint)

proc isBinaryTarget(target: CShaderTarget): bool =
  target in {csVulkan10, csVulkan11, csVulkan12, csVulkan13, csVulkan14}

proc formatOf(target: CShaderTarget): ShaderFormat =
  case target:
  of csVulkan10..csVulkan14: sfSPIRV
  of csOpenGL, csOpenGLCompat: sfGLSL
  of csWebGPU: sfWGSL

proc compileResultTo*(shader: CompiledShader, target: CShaderTarget,
                      resultName = "untitled.glsl",
                      openglVersion: int = 430): ShaderResult =
  let compiler = initializeCompiler()
  defer: release(compiler)
  let options = initializeCompileOptions()
  defer: release_proc(options)
  options.applyTarget(target, openglVersion.cint)

  let glslSource = shader.result  ## always starts as GLSL text
  let res = compileIntoSpv(
    compiler, glslSource.cstring, glslSource.len.csize_t,
    ShaderKind.glslInferFromSource, resultName.cstring, "main".cstring, options)
  defer: release_proc_D59E08E4(res)

  if getCompilationStatus(res) != CompilationStatus.success:
    echo "shaderc error: ", getErrorMessage(res)
    return

  let fmt = formatOf(target)
  let shaderResult =
    if fmt == sfSPIRV:
      ## Binary target — copy raw SPIR-V bytes
      let length = getLength(res)
      var spv = newSeq[byte](length)
      copyMem(spv[0].addr, getBytes(res), length)
      ShaderResult(format: fmt, isBinary: true, bytes: spv)
    else:
      ## Text target — shaderc returned transpiled source
      ShaderResult(format: fmt, isBinary: false,
                   source: $cast[cstring](getBytes(res)))

  return shaderResult