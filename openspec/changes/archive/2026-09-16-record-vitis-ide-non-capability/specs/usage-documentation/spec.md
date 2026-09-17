## ADDED Requirements

### Requirement: Soft-CPU software can be built and run without the Vitis IDE

Because the Vitis IDE cannot run in this environment, the repository SHALL
provide tooling that covers the work the IDE would otherwise do: creating a
software platform (BSP) and an application from a Vivado hardware design, and
rebuilding that application and getting it running on the board after a source
edit. The tooling SHALL work with hardware projects created in the Vivado GUI,
not only with the repository's scripted example designs. The documentation
SHALL describe this path as the supported way to write and run C for the soft
CPU.

#### Scenario: Creating a platform and application for a design
- **WHEN** the user has exported a hardware design (`.xsa`, with bitstream) from Vivado and runs the repository's platform/application creation tooling against that project
- **THEN** a software platform and an application are created and built without the IDE, and the resulting application is compiled from a source file in a single documented location that the user edits

#### Scenario: Rebuild and run after editing C
- **WHEN** the user edits that source file and runs the repository's build-and-run tooling for the project
- **THEN** the application is recompiled, merged into the bitstream so the program runs from power-on, and programmed onto the board, with the output observable on the serial console

#### Scenario: Hardware projects created in the Vivado GUI
- **WHEN** the project was created through the Vivado GUI, so its implementation directory and wrapper are named after the project and block design rather than matching the repository's scripted conventions
- **THEN** the tooling locates the implementation outputs and the processor instance from the project itself, rather than requiring the user to rename files or pass their names by hand
