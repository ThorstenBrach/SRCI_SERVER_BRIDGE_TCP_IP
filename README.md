# SRCI_TcpIp_Bridge – PLC as TCP/IP bridge for SRCI

The PLC forwards SRCI telegrams between the Python client
[SRCI_PY](https://github.com/ThorstenBrach/SRCI_CLIENT_PY) and a robot on PROFINET. The whole SRCI
logic – RobotTask, commands, sequences – runs in Python; the PLC only copies bytes. This repository
contains a ready-to-use example for **TwinCAT 3** and one for **CODESYS V3.5**.

```
Python (SRCI_PY)                       PLC (bridge)                              Robot controller
  SrciClient + TcpTransport  --TCP-->  FB_SrciTcpIpBridge  --PROFINET outputs-->  SRCI server
  (cycle 10 ms)              <--TCP--                      <--PROFINET inputs---
```

Protocol (as in `SRCI_PY/docs/TRANSPORT.md`, the same one `TcpTransport` and the
`PlcGatewaySimulator` of the Python tests use):

- The PLC is the TCP server, Python the client. One client at a time; a new client replaces the old one.
- Raw SRCI telegrams without framing, with fixed lengths (e.g. 256/256 bytes).
- Lockstep: Python sends one telegram, the PLC answers with exactly one. The PLC never sends on its own.

## Contents

| Path | Content |
|---|---|
| [`TwinCAT/`](TwinCAT) | TwinCAT 3 solution `SRCI_TcpIp_Bridge.sln`: PLC project with `FB_SrciTcpIpBridge`, `GVL_Bridge`, `MAIN`, and the I/O configuration used with a JAKA MiniCobo (EL6631 PROFINET controller, GSDML of JAKA, modules `SRCI_256_R2P` / `SRCI_256_P2R`) |
| [`Codesys/SRCI_TcpIp_Bridge.xml`](Codesys/SRCI_TcpIp_Bridge.xml) | CODESYS example as PLCopen XML: `FB_SrciTcpIpBridge` (library SysSocket), `GVL_Bridge`, `PLC_PRG` |
| [`Codesys/Source/`](Codesys/Source) | the same CODESYS objects as ST text; `Codesys/st_to_plcopen.py` generates the XML from them |

## FB_SrciTcpIpBridge

Both versions have the same interface:

```
GVL_Bridge.Bridge( Enable            := TRUE,
                   LocalHost         := '',      // '' = all network adapters
                   LocalPort         := 5000,
                   LengthPlcToRob    := 256,     // = PROFINET module size = TcpTransport(..., 256, 256)
                   LengthRobToPlc    := 256,
                   AnswerDelayCycles := 0,
                   RobotOutData      := GVL_Bridge.RobotOutData,   // PROFINET outputs to the robot
                   RobotInData       := GVL_Bridge.RobotInData );  // PROFINET inputs from the robot
```

| Situation | Behaviour |
|---|---|
| Request complete (`LengthPlcToRob` bytes, also in several TCP parts) | copied to `RobotOutData`, answer with `RobotInData` (`LengthRobToPlc` bytes) |
| `AnswerDelayCycles = 0` (default) | the answer holds the inputs of the cycle in which the request was complete |
| `AnswerDelayCycles = n` | the answer is sent n PLC cycles later, after the outputs went out over PROFINET: newer inputs, longer round trip |
| Python reconnects (e.g. after a timeout) | the new client replaces the old one, also after a half-open connection (cable break) |
| Client disconnects | the last telegram stays in the outputs. Its LifeSign no longer changes, so the RC leaves the state INITIALIZED (LifeSign timeout), as with a stopped PLC |
| `Enable = FALSE` | client and server port are closed |
| Start / download | TwinCAT: `FB_SocketCloseAll` closes sockets left open (`CloseAllOnStart`). CODESYS: `FB_exit` closes the sockets, `SO_REUSEADDR` allows to open the port again at once |

Diagnosis: `Listening`, `Connected`, `Connections`, `Telegrams`, `Interval` (time between two
requests = real cycle time of Python), `MaxInterval` (largest gap since the connection – check it
against the LifeSign timeout), `Error`, `ErrorID`, `ErrorStep`. `ErrorID`: TwinCAT Tc2_TcpIp
code, CODESYS runtime error code (CmpErrors, e.g. 16#207 address in use); 16#FFFD buffers too
small for the telegram lengths, 16#FFFE invalid step.

## TwinCAT 3

1. Open `TwinCAT/SRCI_TcpIp_Bridge.sln` and choose your target system.
2. **PROFINET:** the example contains the configuration of a JAKA MiniCobo (EL6631, slot 11
   `SRCI_256_R2P`, slot 12 `SRCI_256_P2R`). For another robot add it with its GSDML as PROFINET
   device and link `GVL_Bridge.RobotInData` with the input module of the SRCI telegrams,
   `RobotOutData` with the output module.
   - If the GSDML splits the telegram into several modules (e.g. 4 × 64 bytes), link the array
     sections one by one in the order of the telegram.
   - The lengths in `MAIN` must match the module size; Python uses the same lengths.
3. **Task:** the example runs with 10 ms (tested with the JAKA, PROFINET cycle 8 ms).
   `FB_SocketReceive`/`FB_SocketSend` need at least one cycle each, so a request takes 2 to 3 PLC
   cycles; a shorter task (1 to 2 ms) gives shorter round trips.
4. **Network:** TF6310 uses the TCP/IP stack of Windows / TwinCAT BSD. Python connects through a
   normal network adapter, not through the PROFINET adapter. Allow the incoming TCP port 5000 in
   the firewall.
5. **License:** TF6310 (TCP/IP); a trial license is enough for tests.

Libraries: Tc2_Standard, Tc2_System, Tc2_TcpIp (the SRCI RobotLibrary is not needed).

## CODESYS V3.5

1. Create a standard project for your controller (e.g. CODESYS Control Win / RTE / for Linux, a
   PLC with CODESYS runtime).
2. **Import:** select the project (top node), then *Project → Import PLCopenXML…* →
   `Codesys/SRCI_TcpIp_Bridge.xml`. The dialog shows the Application with `PLC_PRG`, `GVL_Bridge`
   and the folder `Bridge` (`FB_SrciTcpIpBridge` with its method `FB_exit`); confirm to replace
   the existing `PLC_PRG`.
3. **Libraries:** add **SysSocket** in the library manager (`SysSocket Implementation`, CODESYS).
   Standard (for `LEN`, `TON`) is part of every project.
4. **Task:** call `PLC_PRG` in a cyclic task (e.g. 2 to 10 ms) – the same task that is the bus
   cycle task of the PROFINET controller, so the telegram goes out in the cycle in which it was
   received. The sockets are non-blocking: a request and its answer usually take one PLC cycle.
5. **PROFINET:** add *Ethernet → PROFINET IO Controller* and the robot from its GSDML (device
   repository) with the modules of the SRCI telegrams. In the *I/O Mapping* of the modules map the
   channel of the input module to `GVL_Bridge.RobotInData` and the output module to
   `GVL_Bridge.RobotOutData` (*Map to existing variable*). If the module data are shown as
   single bytes, map them element by element in the order of the telegram.
6. **Network:** Python connects to an IP address of the controller on a normal network adapter;
   allow TCP port 5000 in the firewall of the controller.

## Python side

```python
from srci.api import SrciClient
from srci.fb import MC_EnableRobotFB, MC_GroupResetFB, MC_MoveAxesAbsoluteFB
from srci.transport import TcpTransport

transport = TcpTransport("192.168.2.10", 5000, 256, 256, response_timeout=0.1)
with SrciClient(transport) as client:
    # Python is not real-time (scheduler, GC) and some RCs pause their LifeSign: some reserve
    client.program.ParCfg.Com.LifeSignTimeOut = 500
    client.wait_initialized()
    client.execute(MC_GroupResetFB())
    enable = client.enable(MC_EnableRobotFB())
    move = MC_MoveAxesAbsoluteFB()
    move.ParCmd.JointPosition.J1 = 10.0
    client.execute(move)
    client.disable(enable)
```

`transport.statistics` shows the round-trip times on the Python side, `MaxInterval` the side of
the PLC. Without a robot you can test the connection with an echo: declare `RobotInData` /
`RobotOutData` without I/O link and add `RobotInData := RobotOutData` in the program – Python then
receives its own telegram.

## Status

| Example | Status |
|---|---|
| TwinCAT 3 | runs with a JAKA MiniCobo (SRCI 1.1, profile Core) and SRCI_PY |
| CODESYS | **not compiled and not tested yet.** Written for the library SysSocket (functions `SysSockCreate`, `SysSockBind`, `SysSockListen`, `SysSockAccept`, `SysSockRecv`, `SysSockSend`, `SysSockClose`, non-blocking via `SysSockIoctl(SOCKET_FIONBIO)`) after the CODESYS online help. Please report what had to be changed |

## Safety

SRCI is not a safety interface, and Python runs without real time. Emergency stop, safeguards and
safe speeds belong to the safety controller of the robot or the safety PLC. If Python stops, the
bridge stops forwarding; the RC detects it by the LifeSign and leaves the initialization. Whether
it also stops the motion is defined by the manufacturer – check it before the first test with a
real robot.

## License

MIT, see [LICENSE](LICENSE). The software is based on the SRCI technology of PROFIBUS and PROFINET
International (PI) but is not an official publication of PI. It is provided without any guarantee;
any use is at your own risk.
