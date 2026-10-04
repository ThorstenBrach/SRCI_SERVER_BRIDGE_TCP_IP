{attribute 'qualified_only'}
// -------------------------------------------------------------------------
//  SRCI Robot Library
// -------------------------------------------------------------------------
//
//  Object:      GVL_Bridge (CODESYS)
//  Author:      Thorsten Brach
//  Date:        2026-10-04
//
//  Description:
//    PROFINET process data of the robot and the TCP/IP bridge instance.
//    Map RobotInData / RobotOutData in the I/O mapping of the PROFINET device
//    (modules of the SRCI telegrams) with "Map to existing variable".
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
VAR_GLOBAL
  /// Telegram RC -> PLC: PROFINET inputs of the robot (map to the input module(s) of the RC)
  RobotInData  : ARRAY[0..255] OF BYTE;
  /// Telegram PLC -> RC: PROFINET outputs of the robot (map to the output module(s) of the RC)
  RobotOutData : ARRAY[0..255] OF BYTE;
  /// TCP/IP server for the SRCI client in Python
  Bridge       : FB_SrciTcpIpBridge;
END_VAR
