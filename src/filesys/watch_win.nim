import winlean

type
  WatcherImpl = object
    ## Holds the OVERLAPPED handle and the buffer used by
    ## ReadDirectoryChangesW.  The watch thread is stored in the Watcher
    ## itself (see below).
    rootPath:     string
    dirHandle:    Handle       ## Handle opened with FILE_FLAG_OVERLAPPED
    overlapped:   OVERLAPPED
    ## Rename pairing: when FILE_ACTION_RENAMED_OLD_NAME is seen we park
    ## the old path here until FILE_ACTION_RENAMED_NEW_NAME arrives.
    pendingRenameOld: string

const
  FILE_LIST_DIRECTORY          = 0x00000001'i32
  FILE_FLAG_BACKUP_SEMANTICS   = 0x02000000'i32
  FILE_FLAG_OVERLAPPED         = 0x40000000'i32
  FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001'i32
  FILE_NOTIFY_CHANGE_DIR_NAME  = 0x00000002'i32
  FILE_NOTIFY_CHANGE_LAST_WRITE= 0x00000010'i32

  FILE_ACTION_ADDED              = 1'u32
  FILE_ACTION_REMOVED            = 2'u32
  FILE_ACTION_MODIFIED           = 3'u32
  FILE_ACTION_RENAMED_OLD_NAME   = 4'u32
  FILE_ACTION_RENAMED_NEW_NAME   = 5'u32

  ERROR_NOTIFY_ENUM_DIR          = 1022'u32
  INFINITE_TIMEOUT               = 0xFFFFFFFF'u32

type
  FILE_NOTIFY_INFORMATION {.packed.} = object
    nextEntryOffset: DWORD
    action:          DWORD
    fileNameLength:  DWORD
    ## fileName follows immediately in memory as a variable-length UTF-16LE
    ## string; we read it via pointer arithmetic.

proc waitForSingleObject(hHandle: Handle; dwMilliseconds: DWORD): DWORD {.
    importc: "WaitForSingleObject", dynlib: "kernel32", stdcall.}

proc readDirectoryChangesW(
  hDirectory:          Handle,
  lpBuffer:            pointer,
  nBufferLength:       DWORD,
  bWatchSubtree:       WINBOOL,
  dwNotifyFilter:      DWORD,
  lpBytesReturned:     ptr DWORD,
  lpOverlapped:        ptr OVERLAPPED,
  lpCompletionRoutine: pointer
): WINBOOL {.importc: "ReadDirectoryChangesW", dynlib: "kernel32", stdcall.}

proc getOverlappedResult(
  hFile:            Handle,
  lpOverlapped:     ptr OVERLAPPED,
  lpNumberOfBytesTransferred: ptr DWORD,
  bWait:            WINBOOL
): WINBOOL {.importc: "GetOverlappedResult", dynlib: "kernel32", stdcall.}

proc createEventW(
  lpEventAttributes: pointer,
  bManualReset:      WINBOOL,
  bInitialState:     WINBOOL,
  lpName:            WideCString
): Handle {.importc: "CreateEventW", dynlib: "kernel32", stdcall.}

proc cancelIoEx(hFile: Handle, lpOverlapped: ptr OVERLAPPED): WINBOOL {.
  importc: "CancelIoEx", dynlib: "kernel32", stdcall.}

proc getLastError(): DWORD {.importc: "GetLastError", dynlib: "kernel32", stdcall.}

const OPEN_EXISTING = 3'u32

proc newWatcherImpl(rootPath: string): WatcherImpl =
  result.rootPath = rootPath
  result.dirHandle = createFileW(
    newWideCString(result.rootPath.cstring).toWideCString,
    DWORD(FILE_LIST_DIRECTORY),
    DWORD(1 or 2 or 4),        # FILE_SHARE_READ | WRITE | DELETE
    nil,
    OPEN_EXISTING.DWORD,
    DWORD(FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED),
    Handle(0))

  if result.dirHandle == Handle(-1):
    raiseOSError(osLastError())
  # Create a manual-reset event for the OVERLAPPED structure.
  result.overlapped = OVERLAPPED()
  result.overlapped.hEvent = createEventW(nil, 1.WINBOOL, 0.WINBOOL, nil)
