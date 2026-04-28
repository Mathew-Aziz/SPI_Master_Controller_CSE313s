Below is a **single, unified SV-only test plan** that ties together:

- **Spec functional requirements R1–R25**
- **Grading contract mandatory tests (10 tests)**
- **Coverage targets (modes/width/order, DIV, DELAY, FIFO occupancy, IRQ)**
- **Check strategy** (scoreboard vs SVA vs directed checks)

It is in the exact **5-column format** you requested.

> Notes for your team:
> - “Stimulus generation” describes *how* you’ll create the scenario (directed + constrained-random).
> - “Functional coverage” describes *bins* you must hit.
> - “Functionality check” states *how you detect bugs*: scoreboard comparison, SVA, direct register reads, timing measurement.
> - Some items are “undefined behavior” in the spec (illegal sequences). For those you can still check **non-crash**, **reserved offset behavior**, and **R25 sampled-at-start** aspects where defined.

---

## Master Test Plan Table (SV-only)

### A) APB/Register correctness + Reset + Reserved space

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-REG-01 | **R2** Reset values: all regs return specified reset after PRESETn | Directed: apply PRESETn low ≥2 cycles, release; read CTRL/STATUS/CLK_DIV/SS_CTRL/INT_EN/INT_STAT/DELAY | Coverpoint: “reset observed” per register | Scoreboard/Direct check: APB reads compare vs reset constants |
| TP-REG-02 | **R1** R/W registers read back last written value (RO masked) | Directed + random: for each RW reg, write multiple patterns; read back | Per-register write/read bins; CTRL fields bins | Scoreboard compare on readbacks with RO mask |
| TP-REG-03 | **R22** APB always zero-wait: PREADY=1 always, PSLVERR=0 always | Always-on during all tests | Coverage: count of APB reads/writes; include at least one access per reg | SVA bound to wrapper: `PREADY==1`, `PSLVERR==0`, plus APB protocol assertions |
| TP-REG-04 | **R23** Reserved offsets (0x24+) read 0, writes ignored | Directed: read several addresses ≥0x24; write random then read back | Bin: reserved_read, reserved_write | Scoreboard/direct: read data==0; optionally check no status side-effects |
| TP-REG-05 | **R3** EN=0 holds shifter+FIFOs in reset; SCLK idle; SS forced high regardless SS_CTRL | Directed: set SS_CTRL to assert low, set EN=0, write TX_DATA, observe SS_n/SCLK/BUSY | Bin: EN0 behavior exercised | SVA: SS forced high when EN=0; SCLK idle; Scoreboard: TX write ignored when EN=0 (per spec) |

---

### B) SPI mode correctness + Bit order + Width behavior + BUSY timing

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-SPI-01 | **R4** SCLK idle polarity matches CPOL whenever BUSY=0 | Directed sweep: MODE=0..3; no transfer and between transfers | Bin: 4 modes idle check | SVA in `u_core`: when BUSY==0, SCLK==CPOL |
| TP-SPI-02 | **R5** MOSI stable around sample edge; changes on launch edge per CPHA | Directed: for each MODE, transmit known pattern; monitor MOSI around sample edges | Bin: mode x (edge type) exercised | SVA “wire stability” around sample edge; monitor-based check that MOSI only changes at launch edges |
| TP-SPI-03 | **R6** MSB-first shifts [WIDTH-1] first; LSB-first shifts [0] first (TX and RX) | Directed: patterns like 0x81/0x3C, 16’h8001, 32’h8000_0001; run for both LSB_FIRST values | Cross bins: mode×width×order (24 bins) | SPI monitor reconstructs MOSI bit stream; scoreboard compares expected TX stream + received RX word |
| TP-SPI-04 | **R7** Transfer lasts exactly WIDTH SCLK cycles; BUSY asserted throughout; deasserts 1 PCLK after last sample edge | Directed: run 8/16/32; count sample edges; measure BUSY timing precisely | Width bins 8/16/32 plus boundary patterns | Checker: cycle counter in monitor; SVA for BUSY timing (optional), scoreboard check for exact cycle counts |
| TP-SPI-05 | **R25** DIV/MODE/WIDTH/LSB_FIRST sampled at transfer start and held for that transfer | Directed: start transfer; while BUSY=1 attempt to change CTRL.MODE/WIDTH/LSB_FIRST/CLK_DIV; verify current transfer unchanged (next transfer may change) | Bin: “mid-transfer write attempted” per field | Monitor/scoreboard: current transfer uses original settings; next transfer uses updated settings |

---

### C) Clock divider behavior (SCLK frequency formula)

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-CLK-01 | **R8** SCLK = PCLK/(2*(DIV+1)) for all DIV in [0..65535] | Directed corners + random: DIV = 0,1,2,3,255,1024,65535 + random 10 values | Coverage bins: listed corners + random-range bin | Monitor counts PCLK cycles per SCLK toggle; compare exact expected half-period=DIV+1 |
| TP-CLK-02 | **R24** DIV=0 yields SCLK=PCLK/2 (not divide-by-zero) | Directed: set DIV=0, perform transfer | Bin: DIV==0 hit | Timing check from monitor |

---

### D) FIFO correctness (depth, ordering, overflow/underflow rules)

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-FIFO-01 | **R9** TX_DATA accepted while !TX_FULL; FIFO order preserved | Directed: push N words (N=1,4,8) then transmit; ensure order | TX occupancy bins: empty,1,4,7,full | Scoreboard models TX queue and compares MOSI transfer order |
| TP-FIFO-02 | **R11** TX depth exactly 8; TX_FULL asserts on 8th entry | Directed: push 8 entries; check TX_FULL; push 7 check not full | Bin: TX full transition on 8th | Direct STATUS read + backdoor peek optional; scoreboard validates full condition |
| TP-FIFO-03 | **R10** RX_DATA reads pop in FIFO order when !RX_EMPTY | Directed: generate multiple transfers, then read RX_DATA repeatedly | RX occupancy bins empty,1,4,7,full | Scoreboard models RX queue; compare popped words |
| TP-FIFO-04 | **R12** RX depth exactly 8; RX_FULL asserts on 8th received | Directed: do 8 transfers without reading; check RX_FULL | Bin: RX full transition on 8th | Direct STATUS read + scoreboard |
| TP-FIFO-05 | **R13** TX write while full is discarded, sets STATUS.TX_OVF and INT_STAT[TX_OVF] | Directed: fill TX to 8, then extra write | Bin: TX overflow event | Scoreboard checks discard + TX_OVF sticky; interrupt_test also validates INT_STAT |
| TP-FIFO-06 | **R14** Transfer completing while RX_FULL discards received word and sets RX_OVF | Directed: fill RX with 8 (don’t read), do another transfer | Bin: RX overflow event | Scoreboard expects discard and RX_OVF sticky; compare RX queue length unchanged |
| TP-FIFO-07 | **R15** RX_DATA read while empty returns 0 and does NOT set RX_OVF | Directed: ensure RX empty; read RX_DATA multiple times | Bin: RX empty read | Direct check read==0; check RX_OVF unchanged in STATUS/INT_STAT |

---

### E) SS_n behavior

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-SS-01 | **R20** SS_n[i] = !SS_EN[i] OR SS_VAL[i] combinational; IP never drives autonomously | Directed: toggle SS_CTRL values while idle; verify SS_n follows immediately; attempt transfers with SS not asserted | Bin: each SS bit toggled at least once | Direct sampling of SS_n vs expected combinational equation; SVA optional |
| TP-SS-02 | Part of timing contract: SS must remain asserted across transfer | Directed: assert SS, start transfer, attempt to deassert mid-transfer (software mistake) | Bin: SS deassert attempt | SVA: “SS held asserted while BUSY” (will flag if DUT doesn’t enforce? Note: spec says software MUST hold; DUT doesn’t auto toggle. Here you mainly ensure your monitor/test respects precondition; use as negative test only if desired.) |

> Caution: The spec says software must hold SS asserted; the DUT won’t fix your mistake. Use TP-SS-02 carefully: treat it as **negative/undefined** and don’t fail golden unless you explicitly expect undefined.

---

### F) Interrupt controller correctness (sticky, mask, W1C, race)

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-IRQ-01 | **R16** IRQ = OR(INT_STAT & INT_EN) at all times; mask gates IRQ only | Directed: for each interrupt source, cause event with mask=0 and mask=1 | Bin: each interrupt asserted while masked and unmasked | SVA: IRQ equivalence every PCLK; scoreboard also checks |
| TP-IRQ-02 | **R17** INT_STAT W1C behavior: write 1 clears; 0 no effect | Directed: set bits via events, then W1C clear single bits, then clear all | Bin: each bit asserted+cleared | Direct register reads + scoreboard |
| TP-IRQ-03 | **R18** W1C race: event coincident with clear => bit remains 1 | Directed: schedule W1C on same cycle as event (use transfer_done timing or overflow timing) | Bin: race case hit at least once | Scoreboard models “event wins”; check INT_STAT still 1 |
| TP-IRQ-04 | Interrupt sources list coverage (TRANSFER_DONE, RX_OVF, TX_OVF, RX_FULL, TX_EMPTY) | Directed: create each event (FIFO fill/empty, overflow, transfer completion) | Bin: each interrupt source observed | Scoreboard + reads |

---

### G) Loopback mode

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-LB-01 | **R19** LOOPBACK routes MOSI internally to RX; external MISO ignored | Directed: enable LOOPBACK; drive random MISO; send known TX words | Bin: loopback per width (8/16/32 at least once) | Scoreboard expects RX==TX; monitor ensures MISO changes don’t affect |

---

### H) Inter-transfer delay behavior

| Label | Design Requirement Description | Stimulus generation | Functional coverage | Functionality check |
|---|---|---|---|---|
| TP-DLY-01 | **R21** DELAY idle half-cycles inserted between consecutive transfers while BUSY stays 1 | Directed: queue 2+ TX words; test DELAY=0,1,>=128 | Bin: DELAY 0, 1, >=128 | Monitor counts idle SCLK half-cycles between transfers; BUSY must stay 1 |
| TP-DLY-02 | DELAY written during BUSY takes effect next transfer | Directed: start transfer; write DELAY mid-busy; verify current gap uses old, next uses new | Bin: “delay updated mid-busy” | Monitor/scoreboard timing check |

---

## 3) Mandatory test files → which plan items they must implement

This helps the team implement exactly what the grader expects.

### `sanity_test`
- TP-REG-01 (basic reset sanity), TP-SPI-01/04 (basic), TP-FIFO-01 basic ordering, TP-SS-01 basic SS use

### `reg_access_test`
- TP-REG-01/02/03/04 (+ TP-REG-05 optional)

### `mode_coverage_test`
- TP-SPI-01/02/03/04 (+ some TP-SPI-05 for sampled-at-start)

### `width_coverage_test`
- TP-SPI-04/05 (strong) + boundary patterns of TP-SPI-03

### `fifo_stress_test`
- TP-FIFO-01/02/03/04, optionally trigger TP-FIFO-05/06 during stress

### `interrupt_test`
- TP-IRQ-01/02/03/04 (must hit all 5 sources and masked+unmasked+clear+race)

### `clk_div_corner_test`
- TP-CLK-01/02 (+ TP-SPI-05 sampled-at-start with mid-transfer DIV write)

### `loopback_test`
- TP-LB-01

### `delay_transfer_test`
- TP-DLY-01/02

### `error_injection_test`
- TP-FIFO-05/06/07, TP-REG-04 (reserved offsets), TP-REG-05 (EN=0 ignored TX writes), plus illegal width attempt (log-only / robustness)

---

## 4) Extra scenarios (to catch *more* of the 28 hidden bugs)

These are not extra required test *files*—they can be added inside existing tests or as additional tests if you have runtime budget.

| Label | Extra scenario (why it catches bugs) | Stimulus | Coverage | Check |
|---|---|---|---|---|
| X-01 | **Back-to-back transfers with SS held low** (common bug: SS glitches or BUSY drops) | assert SS once, queue many TX, no SS toggles | Long burst bin | Monitor SS_n never rises; BUSY rules |
| X-02 | **Switch SS lines between transfers** (bug: wrong SS bit mapping) | use SS0..SS3 one at a time | each SS used | direct SS_n equation check |
| X-03 | **INT_STAT precedence** when multiple interrupts happen same time | cause RX_FULL and TRANSFER_DONE near same moment | multi-bit set bin | scoreboard expects both bits set |
| X-04 | **TX_EMPTY interrupt edge** correctness (often wrong: level vs edge) | create transition non-empty→empty repeatedly | repeated transitions | compare expected INT_STAT behavior (sticky) |
| X-05 | **Random DIV + random DELAY + random mode/width** constrained regression mini-test | randomize within legal set; run short loops | random bins fill gaps | scoreboard + SVA |
| X-06 | **RX_DATA reads during BUSY** (should still behave: pop only on read, not time-based) | read RX_DATA while transfer active | bin: read-during-busy | scoreboard ensures pops only when expected |
| X-07 | **CTRL.EN 1→0 flushes FIFOs & resets shifter but does not clear INT_STAT** | create pending TX/RX and INT_STAT bits, then disable | bin: en-toggle flush | check FIFOs empty, BUSY idle, INT_STAT preserved |
| X-08 | **Loopback + LSB-first + width=32** (hard corner) | combine all corners | loopback corner bin | RX==TX exactly |

These extras are especially good at catching “seeded bug” style issues (off-by-one, wrong gating, wrong sampling, wrong sticky clearing).

---

## 5) How this achieves “aim for 28/28”
You can’t guarantee 28/28 without knowing the staff bug catalog, but this plan maximizes your chance because it:
- hits every spec requirement R1–R25 strongly,
- stresses **race conditions**, **edge cases**, **state transitions**, and **corner timing** (typical seeded-bug targets),
- uses **three independent detection methods**:
  1) scoreboard model (spec-based),
  2) SVA invariants,
  3) directed measurements (timing, register readback).

---

If you want, I can turn this into a **ready-to-paste `docs/test_plan.pdf` outline** (sections, subsections, and tables), and also provide a **simple “coverage closure checklist”** that says which test hits which bin so your team doesn’t miss the 85% functional coverage gate.