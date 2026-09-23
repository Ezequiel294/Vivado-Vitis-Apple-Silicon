## MODIFIED Requirements

### Requirement: Soft-CPU software can be built and run without the Vitis IDE

Because the Vitis IDE cannot run in this environment, the repository SHALL
provide tooling that covers the work the IDE would otherwise do: creating a
software platform (BSP) and an application from a Vivado hardware design, and
rebuilding that application and getting it running on the board after a source
edit. The tooling SHALL work with hardware projects created in the Vivado GUI,
not only with the repository's scripted example designs. The documentation
SHALL describe this path as the supported way to write and run C for the soft
CPU.

An application SHALL be creatable either from a source file the user writes or
from an application template supplied by the toolchain, and the tooling SHALL
NOT substitute the user's source into an application created from a template.
The compiler optimization level and debug level SHALL be selectable when the
application is created and changeable afterwards, since assignments specify
them. The size of the compiled program SHALL be reported by the build.

#### Scenario: Creating a platform and application for a design
- **WHEN** the user has exported a hardware design (`.xsa`, with bitstream) from Vivado and runs the repository's platform/application creation tooling against that project
- **THEN** a software platform and an application are created and built without the IDE, and the resulting application is compiled from a source file in a single documented location that the user edits

#### Scenario: Rebuild and run after editing C
- **WHEN** the user edits that source file and runs the repository's build-and-run tooling for the project
- **THEN** the application is recompiled, merged into the bitstream so the program runs from power-on, and programmed onto the board, with the output observable on the serial console

#### Scenario: Hardware projects created in the Vivado GUI
- **WHEN** the project was created through the Vivado GUI, so its implementation directory and wrapper are named after the project and block design rather than matching the repository's scripted conventions
- **THEN** the tooling locates the implementation outputs and the processor instance from the project itself, rather than requiring the user to rename files or pass their names by hand

#### Scenario: Creating an application from a toolchain-supplied template
- **WHEN** the user names an application template that the installed toolchain provides, instead of writing their own source
- **THEN** the application is created with that template's complete source set, its board-support library dependencies and its linker settings intact, and none of them are replaced by the project's own source file — neither when the application is created nor on any later rebuild

#### Scenario: A template the design cannot support
- **WHEN** the named template requires hardware the design does not contain, or a template of that name is not installed
- **THEN** the tooling fails with a message naming the template and what it requires, rather than creating a partially configured application

#### Scenario: Selecting compiler optimization and debug level
- **WHEN** an assignment requires the program to be compiled at a particular optimization level and without debug information, and the user requests those settings through the tooling
- **THEN** the application is built with those settings, and the settings actually used are visible in the build output

#### Scenario: Reading the compiled program's size
- **WHEN** an application finishes building
- **THEN** the build output reports the compiled size of the program, broken down by section, without the user running a separate command
