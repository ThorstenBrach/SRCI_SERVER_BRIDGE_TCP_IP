# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Added
 - TwinCAT 3 example (`TwinCAT/SRCI_TcpIp_Bridge.sln`): `FB_SrciTcpIpBridge` (Tc2_TcpIp, TF6310),
   `GVL_Bridge`, `MAIN`, I/O configuration of a JAKA MiniCobo (EL6631 PROFINET controller,
   modules `SRCI_256_R2P` / `SRCI_256_P2R`)
 - CODESYS example (`Codesys/SRCI_TcpIp_Bridge.xml`, PLCopen XML for the import, and the ST sources
   in `Codesys/Source/`): `FB_SrciTcpIpBridge` with the library SysSocket (non-blocking sockets,
   `FB_exit` closes the sockets), `GVL_Bridge`, `PLC_PRG`; `Codesys/st_to_plcopen.py` generates
   the XML from the sources
 - README, CHANGELOG, LICENSE (MIT)

### Changed
 - Renamed from SRCI_TcpGateway to SRCI_TcpIp_Bridge: `FB_SrciTcpGateway` -> `FB_SrciTcpIpBridge`,
   `GVL_Gateway` (instance `Gateway`) -> `GVL_Bridge` (instance `Bridge`), solution and PLC project
   `SRCI_TcpIp_Bridge`
 - TwinCAT: the reference to TcUnit was removed (not used)

### Fixed
 - CODESYS: the PLCopen XML is valid against the PLCopen schema TC6 XML V2.01 (a plain `STRING`
   was written as `<STRING />` instead of `<string />`)

### Tested with
 - TwinCAT 3 + JAKA MiniCobo (controller 1.7.1, SRCI 1.1, profile Core) and SRCI_PY
 - CODESYS: not compiled and not tested yet
