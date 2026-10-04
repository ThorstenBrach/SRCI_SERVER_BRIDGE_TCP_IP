/// SRCI bridge: Python (TCP/IP) <-> robot controller (PROFINET)
PROGRAM PLC_PRG
// -------------------------------------------------------------------------
//  SRCI Robot Library
// -------------------------------------------------------------------------
//
//  Object:      PLC_PRG (CODESYS)
//  Author:      Thorsten Brach
//  Date:        2026-10-04
//
//  Description:
//    Starts the TCP/IP server of the SRCI bridge. Python connects with
//      TcpTransport('<IP of the PLC>', 5000, 256, 256)
//    Call it in the same task as the PROFINET controller (bus cycle task),
//    see README.md.
//
//  Copyright:
//    (C) 2026 Thorsten Brach. All rights reserved
//             Licensed under the MIT License.
//
//  Disclaimer:
//    This project is provided without any guarantee and can be used for
//    private and commercial purposes. Any use is at the user's
//    own risk and responsibility.
//
// -------------------------------------------------------------------------
VAR
  /// Enable the bridge
  Enable : BOOL := TRUE;
END_VAR

  GVL_Bridge.Bridge( Enable            := Enable,
                     LocalHost         := '',
                     LocalPort         := 5000,
                     LengthPlcToRob    := 256,
                     LengthRobToPlc    := 256,
                     AnswerDelayCycles := 0,
                     RobotOutData      := GVL_Bridge.RobotOutData,
                     RobotInData       := GVL_Bridge.RobotInData );

END_PROGRAM
