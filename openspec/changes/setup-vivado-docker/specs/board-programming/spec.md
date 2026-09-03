## Purpose

Connects the Arty FPGA board (A7-100T or S7-25) on the Mac's USB port to the toolchain: JTAG access for Vivado/Vitis running inside the container, direct bitstream programming from the host, and a serial console for programs running on the soft CPU.

## ADDED Requirements

### Requirement: Bitstream can be programmed from the host

A bitstream generated inside the container SHALL be programmable onto the Arty board directly from macOS, without any container involvement, as the baseline programming path.

#### Scenario: Direct programming
- **WHEN** the board is connected via USB and the user runs the host-side programming tool against a `.bit` file from the coursework directory
- **THEN** the FPGA is configured and the design runs on the board (e.g. the Unit 2 LED example responds to switches)

### Requirement: Container tools reach the board over JTAG

Vivado Hardware Manager and the Vitis debugger running inside the container SHALL be able to open the board as a JTAG target through an XVC (Xilinx Virtual Cable) bridge served on the macOS host, since USB devices are not visible inside the container.

#### Scenario: Hardware Manager connects
- **WHEN** the XVC bridge is running on the host with the board connected, and Vivado inside the container opens a hardware target using the XVC URL
- **THEN** the FPGA device is detected and can be programmed from Hardware Manager

#### Scenario: Vitis runs a program on the soft CPU
- **WHEN** a MicroBlaze-style soft CPU is loaded on the FPGA and the user launches "Run on Hardware" from Vitis inside the container via the XVC target
- **THEN** the compiled ELF is downloaded to the CPU over the bridge and executes

### Requirement: Serial console for board programs

Output printed by programs running on the board's soft CPU over the USB UART SHALL be viewable in a terminal on macOS, and keyboard input SHALL reach the program.

#### Scenario: UART round-trip
- **WHEN** a program on the board writes to its UART and the user has the documented serial terminal open on the corresponding `/dev/tty.usbserial*` device at the correct baud rate
- **THEN** the program's output appears in the terminal and typed characters are delivered to the program
