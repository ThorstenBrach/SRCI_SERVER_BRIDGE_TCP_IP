# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Added
 - TwinCAT 3 example (`TwinCAT/SRCI_TcpIp_Bridge.sln`): `FB_SrciTcpIpBridge` (Tc2_TcpIp, TF6310),
   `GVL_Bridge`, `MAIN`, I/O configuration of a JAKA MiniCobo (EL6631 PROFINET controller,
   modules `SRCI_256_R2P` / `SRCI_256_P2R`)
 - CODESYS example: project `Codesys/SRCI_TcpIp_Bridge.project` (CODESYS V3.5 SP22 Patch 2) with
   `FB_SrciTcpIpBridge` (library SysSocket, non-blocking sockets, `FB_exit` closes the sockets),
   `GVL_Bridge`, `PLC_PRG`; libraries SysSocket and SysTypes2 Interfaces
 - README, CHANGELOG, LICENSE (MIT)

### Changed
 - Renamed from SRCI_TcpGateway to SRCI_TcpIp_Bridge: `FB_SrciTcpGateway` -> `FB_SrciTcpIpBridge`,
   `GVL_Gateway` (instance `Gateway`) -> `GVL_Bridge` (instance `Bridge`), solution and PLC project
   `SRCI_TcpIp_Bridge`
 - TwinCAT: the reference to TcUnit was removed (not used)

### Tested with
 - TwinCAT 3 + JAKA MiniCobo (controller 1.7.1, SRCI 1.1, profile Core) and SRCI_PY
 - CODESYS: project created in CODESYS V3.5 SP22 Patch 2, not tested with a robot yet
