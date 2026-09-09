# usage-documentation Specification

## Purpose
A README that lets the user (or a classmate with the same Mac setup) install and operate the whole environment without needing this conversation: prerequisites, one-time setup, and the day-to-day course workflow.

## Requirements

### Requirement: README documents prerequisites and one-time setup

The repository SHALL contain a `README.md` that lists everything to install on macOS (container runtime with Rosetta, XQuartz, openFPGALoader, and their configuration) and walks through the one-time setup in order: building/starting the container, XQuartz permissions, running the AMD GUI installer with the correct selections (Vivado product incl. Vitis; Artix-7 + Spartan-7 devices only), generating and installing the node-locked license against the container's pinned identity, and installing Digilent board files and XDC constraints.

#### Scenario: Fresh-machine install
- **WHEN** a user with a clean Apple Silicon Mac follows the README top to bottom
- **THEN** they reach a state where Vivado opens, reports a valid license, and lists the Arty A7-100T and Arty S7-25 boards, without consulting any external guide

### Requirement: README documents the daily workflow

The `README.md` SHALL document the recurring usage loop: starting/stopping the environment, where coursework files live on the Mac and in the container, synthesizing and generating a bitstream, programming the board (both the host-direct path and the XVC path), running a compiled program on the soft CPU via the `updatemem` boot-bitstream flow, and opening the serial console. Capabilities that do not work (Vitis "Run/Debug on Hardware") SHALL be documented as such rather than omitted. Known failure modes (XQuartz not accepting connections, XVC bridge not running, board not detected) SHALL each have a short troubleshooting note.

#### Scenario: Routine session
- **WHEN** the user returns to coursework after a break and follows the README's usage section
- **THEN** they can go from powering on the Mac to a programmed board with a serial console open, using only commands given in the README

#### Scenario: Common failure lookup
- **WHEN** the GUI fails to appear or the board is not detected
- **THEN** the README's troubleshooting section names the symptom and gives the checking/fixing command

### Requirement: A runnable test suite verifies the environment

The repository SHALL ship a test suite that exercises each capability of the environment on real hardware, with a README per test stating what it proves, how to run it, its pass criteria and its failure modes. The documentation SHALL state that the suite must be copied into the mounted coursework directory before it will run, since the container cannot see the repository.

#### Scenario: Verifying the environment after a change
- **WHEN** the image, the toolchain, or the host-side bridge tooling changes and the user runs the suite
- **THEN** each test reports a pass or a failure with a machine-checkable signal where one exists, and any test whose result can only be judged by eye says so rather than reporting a pass on the strength of a successful build

#### Scenario: A known limitation stays visible
- **WHEN** a capability is known not to work in this environment
- **THEN** a regression test reproduces the documented failure, and that test reports the limitation *disappearing* as the result that requires the documentation to be updated
