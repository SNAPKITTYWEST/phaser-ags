## ═══════════════════════════════════════════════════════════════════
##  PHASER AGS — Nim AST macros for hardware register generation
##
##  Compile-time register maps from declarative specs.
##  Generates typed read/write/set/clear/toggle accessors with
##  bit-field extraction, all verified at compile time.
##
##  Usage:
##    defRegBlock Uart0, 0x4806A000:
##      defReg thr,  0x00, u32, wo    # write-only
##      defReg rbr,  0x00, u32, ro    # read-only
##      defReg ier,  0x04, u32, rw
##      defReg lcr,  0x0C, u32, rw:
##        defField dllMode, 7, 1      # DLAB bit
##        defField wordLen, 0, 2      # 00=5bit, 01=6bit, 10=7bit, 11=8bit
## ═══════════════════════════════════════════════════════════════════

import std/macros
import std/strutils

type
  AccessKind* = enum
    ro = "ro"      ## Read-only
    wo = "wo"      ## Write-only
    rw = "rw"      ## Read-write

# ─── Volatile memory access ──────────────────────────────────────

template volatileLoad*[T](addr: uint): T =
  ## Read from memory-mapped register
  cast[ptr T](addr)[]

template volatileStore*[T](addr: uint; val: T) =
  ## Write to memory-mapped register
  cast[ptr T](addr)[] = val

# ═══════════════════════════════════════════════════════════════════
#  defReg — Define a single register with typed accessors
#
#  Generates:
#    proc read_<name>(): T          (for ro/rw)
#    proc write_<name>(val: T)      (for wo/rw)
#    proc set_<name>(mask: T)       (for rw)
#    proc clear_<name>(mask: T)     (for rw)
#    proc toggle_<name>(mask: T)    (for rw)
# ═══════════════════════════════════════════════════════════════════

macro defReg*(name: untyped; offset: SomeInteger; typ: typedesc;
              access: static[AccessKind]; body: untyped = newEmptyNode()): untyped =
  let
    regName  = $name
    offVal   = intVal(offset)
    typeName = $typ
    accStr   = $access

  var procs = newStmtList()

  # read accessor
  if accStr in ["ro", "rw"]:
    procs.add quote do:
      proc `name`*(): `typ` {.inline.} =
        volatileLoad[`typ`](blockBase + uint(`offVal`))

  # write accessor
  if accStr in ["wo", "rw"]:
    let writeName = ident("write_" & regName)
    procs.add quote do:
      proc `writeName`*(val: `typ`) {.inline.} =
        volatileStore[`typ`](blockBase + uint(`offVal`), val)

  # set/clear/toggle for rw
  if accStr == "rw":
    let
      setName    = ident("set_" & regName)
      clearName  = ident("clear_" & regName)
      toggleName = ident("toggle_" & regName)
    procs.add quote do:
      proc `setName`*(mask: `typ`) {.inline.} =
        volatileStore[`typ`](blockBase + uint(`offVal`),
          volatileLoad[`typ`](blockBase + uint(`offVal`)) or mask)
      proc `clearName`*(mask: `typ`) {.inline.} =
        volatileStore[`typ`](blockBase + uint(`offVal`),
          volatileLoad[`typ`](blockBase + uint(`offVal`)) and (not mask))
      proc `toggleName`*(mask: `typ`) {.inline.} =
        volatileStore[`typ`](blockBase + uint(`offVal`),
          volatileLoad[`typ`](blockBase + uint(`offVal`)) xor mask)

  # Bit fields inside the register
  if body.kind != nnkEmpty:
    for field in body:
      if field.kind == nnkCall and field[0].eqIdent("defField"):
        let
          fieldName = $field[1]
          bitPos    = intVal(field[2])
          bitWidth  = intVal(field[3])
          mask      = (1'u32 shl bitWidth.uint) - 1'u32
          shift     = bitPos.uint
        let
          readF  = ident(fieldName)
          writeF = ident("write_" & fieldName)
        if bitWidth == 1:
          # Single-bit field → returns bool
          procs.add quote do:
            proc `readF`*(): bool {.inline.} =
              (volatileLoad[`typ`](blockBase + uint(`offVal`)) shr `shift`) and 1'u32 != 0'u32
            proc `writeF`*(val: bool) {.inline.} =
              let cur = volatileLoad[`typ`](blockBase + uint(`offVal`))
              volatileStore[`typ`](blockBase + uint(`offVal`),
                (cur and not `mask` shl `shift`) or (uint(val) shl `shift`))
        else:
          # Multi-bit field → returns uint of field width
          procs.add quote do:
            proc `readF`*(): uint {.inline.} =
              uint((volatileLoad[`typ`](blockBase + uint(`offVal`)) shr `shift`) and `mask`)
            proc `writeF`*(val: uint) {.inline.} =
              let cur = volatileLoad[`typ`](blockBase + uint(`offVal`))
              volatileStore[`typ`](blockBase + uint(`offVal`),
                (cur and not (`mask` shl `shift`)) or (u32(val and `mask`) shl `shift`))

  result = newStmtList(procs)

# ═══════════════════════════════════════════════════════════════════
#  defRegBlock — Define a block of registers at a base address
#
#  Generates a type with a blockBase template and all child register
#  accessors. Each register offset is relative to the base.
# ═══════════════════════════════════════════════════════════════════

macro defRegBlock*(name: untyped; base: SomeInteger; body: untyped): untyped =
  let
    blockName = $name
    baseVal   = intVal(base)

  result = newStmtList()

  # Generate a distinct type for the block
  let typeName = ident(blockName & "Regs")
  result.add quote do:
    type `typeName`* = object
    template blockBase*: uint = uint(`baseVal`)

  # Process each register definition in the body
  for reg in body:
    if reg.kind == nnkCall and reg[0].eqIdent("defReg"):
      # defReg(name, offset, type, access) or defReg(name, offset, type, access, body)
      let
        regName  = reg[1]
        offset   = reg[2]
        typ      = reg[3]
        access   = reg[4]
        hasBody  = reg.len > 5
      if hasBody:
        let regBody = reg[5]
        result.add getAst(defReg(regName, offset, typ, access, regBody))
      else:
        result.add getAst(defReg(regName, offset, typ, access))

# ═══════════════════════════════════════════════════════════════════
#  defCsr — RISC-V CSR accessor macro
#
#  Generates read/write/set/clear for a CSR by number.
#  Uses inline assembly for csrr/csrw/csrs/csrc.
# ═══════════════════════════════════════════════════════════════════

macro defCsr*(name: untyped; csrNum: SomeInteger): untyped =
  let
    csrName = $name
    num     = intVal(csrNum)

  let
    readName  = ident("read_" & csrName)
    writeName = ident("write_" & csrName)
    setName   = ident("set_" & csrName)
    clearName = ident("clear_" & csrName)

  result = quote do:
    proc `readName`*(): uint32 {.inline.} =
      var val: uint32
      asm "csrr %0, %1"
          : "=r"(val)
          : "I"(`num`)
      val
    proc `writeName`*(val: uint32) {.inline.} =
      asm "csrw %0, %1"
          :
          : "I"(`num`), "r"(val)
    proc `setName`*(mask: uint32) {.inline.} =
      asm "csrs %0, %1"
          :
          : "I"(`num`), "r"(mask)
    proc `clearName`*(mask: uint32) {.inline.} =
      asm "csrc %0, %1"
          :
          : "I"(`num`), "r"(mask)

# ═══════════════════════════════════════════════════════════════════
#  defCsrBlock — Define all RISC-V CSRs in one block
#
#  Usage:
#    defCsrBlock RvCsr:
#      defCsr mstatus,  0x300
#      defCsr mie,      0x304
#      defCsr mtvec,    0x305
# ═══════════════════════════════════════════════════════════════════

macro defCsrBlock*(name: untyped; body: untyped): untyped =
  result = newStmtList()
  for csr in body:
    if csr.kind == nnkCall and csr[0].eqIdent("defCsr"):
      let
        csrName = csr[1]
        csrNum  = csr[2]
      result.add getAst(defCsr(csrName, csrNum))

# ═══════════════════════════════════════════════════════════════════
#  defField — Bit field helper (used inside defReg body)
#
#  defField name, bitPosition, bitWidth
#  Generates typed read/write for that field slice.
# ═══════════════════════════════════════════════════════════════════

macro defField*(name: untyped; bit: SomeInteger; width: SomeInteger): untyped =
  discard  # handled by defReg's body parser
