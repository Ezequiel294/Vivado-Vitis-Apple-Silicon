## MODIFIED Requirements

### Requirement: Container tools reach the board over JTAG

Vivado Hardware Manager and the Vitis debugger running inside the container SHALL be able to open the board as a JTAG target through an XVC (Xilinx Virtual Cable) bridge served on the macOS host, since USB devices are not visible inside the container.

#### Scenario: Hardware Manager connects
- **WHEN** the XVC bridge is running on the host with the board connected, and Vivado inside the container opens a hardware target using the XVC URL
- **THEN** the FPGA device is detected and can be programmed from Hardware Manager

#### Scenario: On-chip debug cores are reachable
- **WHEN** a design containing an ILA and/or VIO is running on the FPGA and Hardware Manager opens the XVC target with the design's `.ltx` probes file
- **THEN** ILA captures can be uploaded and VIO probes read and driven over the bridge

#### Scenario: A program is loaded onto the soft CPU
- **WHEN** the user wants a compiled ELF to run on a MicroBlaze-style soft CPU
- **THEN** the ELF is merged into the bitstream with `updatemem` and the program executes from power-on

#### Scenario: A program larger than the default local memory
- **WHEN** the design gives the soft CPU a local memory substantially larger than the default, and a program that needs that space is merged into the bitstream
- **THEN** the merge covers the whole local memory and the program runs correctly from power-on, with no separate step or option required of the user

Vitis "Run/Debug on Hardware" — which downloads the ELF over JTAG via the
MicroBlaze Debug Module — is an explicit **non-capability** of this
environment: openFPGALoader's XVC server mishandles MDM transactions, so
`stop`/`dow`/`con` and breakpoints all fail (journal §15). The `updatemem`
flow above replaces it.

### Requirement: Serial console for board programs

Output printed by programs running on the board's soft CPU over the USB UART SHALL be viewable in a terminal on macOS, and keyboard input SHALL reach the program. It SHALL also be capturable to a file, so that a program's output can be quoted, compared between runs, or submitted as evidence.

#### Scenario: UART round-trip
- **WHEN** a program on the board writes to its UART and the user has the documented serial terminal open on the corresponding `/dev/cu.usbserial*` device (channel B) at the correct baud rate
- **THEN** the program's output appears in the terminal and typed characters are delivered to the program

#### Scenario: Output that uses bare line feeds
- **WHEN** the program ends its lines with a line feed alone, as much toolchain-supplied code does
- **THEN** the documented way of watching the serial console still shows each line starting at the left margin, rather than stair-stepping across the terminal

#### Scenario: Capturing a transcript
- **WHEN** the user wants a record of what a program printed
- **THEN** the documented tooling writes the output to a file as well as showing it, and the file holds the text the program actually sent
